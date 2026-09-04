#!/usr/bin/env bash
# Shared authoritative lane-attempt state.  Source this file; do not edit
# active.yaml directly from a lane lifecycle caller.
#
# API:
#   lane_register <task-id> <lead-session-id> <worktree> <phase> [pid]
#   lane_transition <task-id> <phase> [detail]
#   lane_deregister <task-id> [reason]
#   lane_alive <task-id>                 # 0 live, 1 dead/not-found
#   lane_reconcile                       # marks dead, recovers live orphans
#   lane_count_live <lead-session-id>    # stdout count

# REGISTRY-MUST-LEAVE-GIT-01: BASH_SOURCE[0] is unset (not merely empty) when
# this file is sourced via `eval "$(cat ...)"` or a similar no-file-backing
# path -- under a caller's `set -u` that is a hard "unbound variable" crash,
# not a silently-wrong path. `${BASH_SOURCE[0]:-}` never crashes; when it IS
# empty, fall back to LEADV2_PROJECT_ROOT/CLAUDE_PROJECT_DIR (the same
# resolution order leadv2-active-registry.sh's own root fallback uses) so the
# resolved dir still points at this checkout's scripts/, not some ambient cwd.
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _lv2_lane_state_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  _lv2_lane_state_dir="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}/plugins/leadv2/scripts"
fi
_lv2_lane_state_root() {
  local root="${LEADV2_PROJECT_ROOT:-${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"
  printf '%s' "$root"
}
_lv2_lane_state_path() {
  local root; root="$(_lv2_lane_state_root)"
  if [[ -x "${_lv2_lane_state_dir}/leadv2-state-path.sh" ]]; then
    PROJECT_ROOT="$root" "${_lv2_lane_state_dir}/leadv2-state-path.sh" --no-link active.yaml
  else
    printf '%s/docs/leadv2/active.yaml' "$root"
  fi
}
_lv2_lane_state_lock() {
  local root; root="$(_lv2_lane_state_root)"
  if [[ -x "${_lv2_lane_state_dir}/leadv2-state-path.sh" ]]; then
    PROJECT_ROOT="$root" "${_lv2_lane_state_dir}/leadv2-state-path.sh" --no-link active.yaml.lock
  else
    printf '%s/docs/leadv2/active.yaml.lock' "$root"
  fi
}
_lv2_lane_start_time() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }
_lv2_lane_state_mutate() { # <op> [args...] -- fcntl.flock + atomic rename
  local path lock; path="$(_lv2_lane_state_path)" || return 1; lock="$(_lv2_lane_state_lock)" || return 1
  python3 - "$lock" "$path" "$@" <<'PY'
import datetime, fcntl, os, subprocess, sys, tempfile
try:
    import yaml
except ImportError:
    sys.exit(1)
lock, path, op, *args = sys.argv[1:]
def now(): return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def birth(pid):
    # Test seam is deliberately an observation source, not a liveness override:
    # os.kill below still decides whether the process exists.
    fixture=os.environ.get('LEADV2_LANE_STATE_TEST_BIRTH_FILE','')
    if fixture:
        try:
            for line in open(fixture, encoding='utf-8'):
                key, value=line.rstrip('\n').split('\t', 1)
                if key == str(pid): return ' '.join(value.split())
        except OSError: pass
    try: return ' '.join(subprocess.run(['ps','-o','lstart=','-p',str(pid)], text=True, capture_output=True, timeout=2).stdout.split())
    except Exception: return ''
def alive(row):
    try: pid=int(row.get('pid'))
    except (TypeError, ValueError): return False
    if pid <= 1: return False
    try: os.kill(pid, 0)
    except OSError: return False
    recorded=' '.join(str(row.get('pid_start_time') or row.get('pid_birth') or '').split())
    observed=birth(pid)
    return bool(recorded and observed and recorded == observed)
def event(row, kind, detail=''):
    row.setdefault('lane_events', []).append({'at':now(),'event':kind, **({'detail':detail} if detail else {})})
os.makedirs(os.path.dirname(lock), exist_ok=True)
with open(lock, 'a+') as lf:
  fcntl.flock(lf, fcntl.LOCK_EX)
  os.makedirs(os.path.dirname(path), exist_ok=True)
  try:
    with open(path, encoding='utf-8') as f: data=yaml.safe_load(f) or {}
  except FileNotFoundError: data={}
  if not isinstance(data, dict): sys.exit(1)
  data.setdefault('meta', {}); data.setdefault('sessions', [])
  rows=data['sessions']
  if op == 'register':
    task, lead, worktree, phase, pid = args
    pid = int(pid)
    live=[r for r in rows if r.get('lead_session_id') == lead and not r.get('dead_at') and alive(r)]
    existing=next((r for r in rows if r.get('task_id') == task and not r.get('dead_at')), None)
    # CONCURRENCY-UNLIMITED-LANES-01 (founder order 2026-09-03, verbatim:
    # "колчиество лейнов везде берешь любое") supersedes CONCURRENCY-2-LANES-01.
    # The default is now high enough not to be a wall; LEADV2_LANE_CAP still
    # overrides it per-session, and a value below 1 is treated as unset.
    #
    # Known defect this does NOT fix, filed separately: independent lead
    # sessions all resolve to lead_session_id="direct", so they share one
    # bucket and one another's cap.  Raising the ceiling is the founder's
    # order; attributing lanes to the right session is the real repair.
    try:
      cap = int(os.environ.get('LEADV2_LANE_CAP', '') or 64)
    except ValueError:
      cap = 64
    if cap < 1: cap = 64
    if not existing and len(live) >= cap:
      print('lane cap exceeded: lead_session_id=%s live=%d cap=%d' % (lead, len(live), cap), file=sys.stderr); sys.exit(3)
    if existing:
      existing.update(pid=pid, pid_start_time=birth(pid), worktree=worktree, phase=phase, lead_session_id=lead, dead_at=None, updated_at=now())
      event(existing, 'registered_refresh')
    else:
      row={'task_id':task, 'session_id':lead, 'lead_session_id':lead, 'worktree':worktree, 'phase':phase,
           'pid':pid, 'pid_start_time':birth(pid), 'started_at':now(), 'updated_at':now(), 'dead_at':None,
           'recovered':False, 'lane_events':[]}
      event(row, 'registered'); rows.append(row)
  elif op == 'transition':
    task, phase, detail = args
    row=next((r for r in rows if r.get('task_id') == task and not r.get('dead_at')), None)
    if row is None: sys.exit(4)
    row['phase']=phase; row['updated_at']=now(); event(row, 'transition:'+phase, detail)
  elif op == 'deregister':
    task, reason=args
    row=next((r for r in rows if r.get('task_id') == task and not r.get('dead_at')), None)
    if row:
      row['dead_at']=now(); row['updated_at']=now(); event(row, 'deregistered', reason)
  elif op == 'reconcile':
    root=args[0]
    for row in rows:
      if not row.get('dead_at') and not alive(row):
        row['dead_at']=now(); row['updated_at']=now(); event(row, 'reconciled_dead')
    fixture_wt=os.environ.get('LEADV2_LANE_STATE_TEST_WORKTREES_FILE','')
    try:
      wt=open(fixture_wt, encoding='utf-8').read() if fixture_wt else subprocess.run(['git','-C',root,'worktree','list','--porcelain'], text=True, capture_output=True, timeout=5).stdout
      worktrees=[x[9:] for x in wt.splitlines() if x.startswith('worktree ')]
    except Exception: worktrees=[]
    known={os.path.realpath(str(r.get('worktree') or '')) for r in rows}
    for worktree in worktrees:
      real=os.path.realpath(worktree)
      if '/.claude/worktrees/' not in real or real in known: continue
      fixture=os.environ.get('LEADV2_LANE_STATE_TEST_PS_FILE','')
      try:
        ps=open(fixture, encoding='utf-8').read().splitlines() if fixture else subprocess.run(['ps','-axo','pid=,lstart=,command='], text=True, capture_output=True, timeout=3).stdout.splitlines()
      except Exception: ps=[]
      for line in ps:
        if worktree not in line: continue
        parts=line.strip().split(None, 6)
        if len(parts) < 7: continue
        pid=int(parts[0]); start=' '.join(parts[1:6])
        if pid > 1 and start == birth(pid):
          task=os.path.basename(worktree)
          row={'task_id':task, 'session_id':'recovered', 'lead_session_id':'recovered', 'worktree':worktree,
               'phase':'recovered', 'pid':pid, 'pid_start_time':start, 'started_at':now(), 'updated_at':now(),
               'dead_at':None, 'recovered':True, 'lane_events':[]}
          event(row, 'recovered_orphan'); rows.append(row); known.add(real); break
  elif op == 'count':
    lead=args[0]; print(sum(1 for r in rows if r.get('lead_session_id') == lead and not r.get('dead_at') and alive(r)))
    sys.exit(0)
  elif op == 'alive':
    task=args[0]; row=next((r for r in rows if r.get('task_id') == task and not r.get('dead_at')), None)
    sys.exit(0 if row and alive(row) else 1)
  fd,tmp=tempfile.mkstemp(prefix='.active.yaml.', dir=os.path.dirname(path))
  with os.fdopen(fd,'w',encoding='utf-8') as f: yaml.safe_dump(data,f,default_flow_style=False,sort_keys=False)
  os.replace(tmp,path)
PY
}
lane_register() { _lv2_lane_state_mutate register "$1" "$2" "$3" "$4" "${5:-$$}"; }
lane_transition() { _lv2_lane_state_mutate transition "$1" "$2" "${3:-}"; }
lane_deregister() { _lv2_lane_state_mutate deregister "$1" "${2:-closed}"; }
lane_alive() { _lv2_lane_state_mutate alive "$1"; }
lane_reconcile() { _lv2_lane_state_mutate reconcile "$(_lv2_lane_state_root)"; }
lane_count_live() { _lv2_lane_state_mutate count "$1"; }
lane_adopt_pid() { # <task-id> <lead-session-id> <worktree> <phase> <worker-pid>
  lane_register "$1" "$2" "$3" "$4" "$5" || return $?
  lane_transition "$1" "$4" "worker_pid_adopted"
}
