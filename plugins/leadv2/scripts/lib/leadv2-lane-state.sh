#!/usr/bin/env bash
# Shared authoritative lane-attempt state.  Source this file; do not edit
# active.yaml directly from a lane lifecycle caller.
#
# API:
#   lane_register <task-id> <lead-session-id> <worktree> <phase> [pid] [lead_pid] [lead_pid_birth]
#   lane_transition <task-id> <phase> [detail]
#   lane_deregister <task-id> [reason]
#   lane_alive <task-id>                 # 0 live, 1 dead/not-found
#   lane_reconcile                       # marks dead, recovers live orphans
#   lane_count_live <lead-session-id>    # stdout count
#   lane_lead_alive <lead-session-id>    # 0 live, 1 dead/orphaned/no-data
#                                         # (D6-REGISTRY-LANE-OWNERSHIP-01: raw
#                                         # lead_pid/lead_pid_birth, additive
#                                         # to pid/pid_start_time, so a lane's
#                                         # owning lead process can be checked
#                                         # without re-parsing lead_session_id)

# REGISTRY-MUST-LEAVE-GIT-01 + D6-REGISTRY-LANE-OWNERSHIP-01 (union of two real
# failures, neither of which the other covers):
#  - under `eval "$(cat ...)"` bash leaves BASH_SOURCE[0] UNSET, and a caller's
#    `set -u` then crashes hard ("unbound variable"), not merely resolves wrong;
#  - under zsh BASH_SOURCE does not exist at all, and the sourcing script's $0
#    is the correct stand-in (every current caller, plus the suites, sits one
#    directory below this lib's parent).
# Order: this lib's own path when bash names it; $0 when it names a real file;
# otherwise the project root -- so the resolved dir points at THIS checkout's
# scripts/, never at an ambient cwd. Production writers are bash-shebang.
_lv2_lane_state_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_lv2_lane_state_src" && -f "${0:-}" ]]; then
  _lv2_lane_state_src="$0"
fi
if [[ -n "$_lv2_lane_state_src" ]]; then
  _lv2_lane_state_dir="$(cd "$(dirname "$_lv2_lane_state_src")/.." && pwd)"
else
  _lv2_lane_state_dir="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}/plugins/leadv2/scripts"
fi
unset _lv2_lane_state_src
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
  # _lv2_mutate_path/_lv2_mutate_lock, NOT plain path/lock: in zsh `path` is
  # the tied array of $PATH, so the old names clobbered PATH inside this
  # function and every child lookup (env bash / python3) died with
  # "No such file or directory". Same behavior under bash, zsh-safe by
  # construction.
  local _lv2_mutate_path _lv2_mutate_lock
  _lv2_mutate_path="$(_lv2_lane_state_path)" || return 1
  _lv2_mutate_lock="$(_lv2_lane_state_lock)" || return 1
  python3 - "$_lv2_mutate_lock" "$_lv2_mutate_path" "$@" <<'PY'
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
    task, lead, worktree, phase, pid = args[:5]
    lead_pid = args[5] if len(args) > 5 else ''
    lead_pid_birth = args[6] if len(args) > 6 else ''
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
      if lead_pid: existing['lead_pid'] = int(lead_pid)
      if lead_pid_birth: existing['lead_pid_birth'] = lead_pid_birth
      event(existing, 'registered_refresh')
    else:
      row={'task_id':task, 'session_id':lead, 'lead_session_id':lead, 'worktree':worktree, 'phase':phase,
           'pid':pid, 'pid_start_time':birth(pid), 'started_at':now(), 'updated_at':now(), 'dead_at':None,
           'recovered':False, 'lane_events':[]}
      if lead_pid: row['lead_pid'] = int(lead_pid)
      if lead_pid_birth: row['lead_pid_birth'] = lead_pid_birth
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
  elif op == 'lead_alive':
    # D6-REGISTRY-LANE-OWNERSHIP-01: same liveness pattern as alive(), but
    # keyed on the lead process (lead_pid/lead_pid_birth) rather than the
    # lane's own worker pid -- "is the session that owns these lanes still
    # running", not "is this particular lane's worker still running".
    lead=args[0]
    row=next((r for r in rows if r.get('lead_session_id') == lead and r.get('lead_pid')), None)
    if row is None: sys.exit(1)
    try: lp=int(row.get('lead_pid'))
    except (TypeError, ValueError): sys.exit(1)
    if lp <= 1: sys.exit(1)
    try: os.kill(lp, 0)
    except OSError: sys.exit(1)
    recorded=' '.join(str(row.get('lead_pid_birth') or '').split())
    observed=birth(lp)
    sys.exit(0 if (recorded and observed and recorded == observed) else 1)
  fd,tmp=tempfile.mkstemp(prefix='.active.yaml.', dir=os.path.dirname(path))
  with os.fdopen(fd,'w',encoding='utf-8') as f: yaml.safe_dump(data,f,default_flow_style=False,sort_keys=False)
  os.replace(tmp,path)
PY
}
lane_register() { _lv2_lane_state_mutate register "$1" "$2" "$3" "$4" "${5:-$$}" "${6:-}" "${7:-}"; }
lane_transition() { _lv2_lane_state_mutate transition "$1" "$2" "${3:-}"; }
lane_deregister() { _lv2_lane_state_mutate deregister "$1" "${2:-closed}"; }
lane_alive() { _lv2_lane_state_mutate alive "$1"; }
lane_lead_alive() { _lv2_lane_state_mutate lead_alive "$1"; }
lane_reconcile() { _lv2_lane_state_mutate reconcile "$(_lv2_lane_state_root)"; }
lane_count_live() { _lv2_lane_state_mutate count "$1"; }
lane_adopt_pid() { # <task-id> <lead-session-id> <worktree> <phase> <worker-pid>
  lane_register "$1" "$2" "$3" "$4" "$5" || return $?
  lane_transition "$1" "$4" "worker_pid_adopted"
}
