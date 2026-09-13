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
import datetime, fcntl, os, shlex, subprocess, sys, tempfile
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
def ppid(pid):
    # Like the birth fixture, this seam supplies process observation only;
    # candidate liveness remains governed by birth(pid) == recorded start.
    fixture=os.environ.get('LEADV2_LANE_STATE_TEST_PPID_FILE','')
    if fixture:
        try:
            for line in open(fixture, encoding='utf-8'):
                key, value=line.rstrip('\n').split('\t', 1)
                if key == str(pid): return int(value)
        except (OSError, ValueError): pass
    try: return int(subprocess.run(['ps','-o','ppid=','-p',str(pid)], text=True, capture_output=True, timeout=2).stdout.strip())
    except Exception: return 1
def ancestry():
    result=set(); pid=os.getpid()
    while pid > 1 and pid not in result:
        result.add(pid); pid=ppid(pid)
    return result
def proc_verdict(pid, recorded_birth):
    # LANE-ALIVE-PREDICATE-CALLS-A-LIVE-LANE-DEAD-01: three-valued liveness.
    # kill(pid,0) has THREE answers (rc=0 alive; ESRCH dead; EPERM = process
    # EXISTS under another owner = alive), and a birth value that is empty or
    # unobservable on EITHER side is incomparability, not death. 'unknown'
    # never kills and never restarts: every consumer below treats it as live
    # for kill/restart decisions -- the contract leadv2-orphan-reaper.sh's
    # _owner_death_state already carries (16efd6fa).
    if pid <= 1: return 'dead'
    try: os.kill(pid, 0)
    except ProcessLookupError: return 'dead'   # ESRCH -- the only proof of death
    except PermissionError: pass               # EPERM -- process exists, other owner
    except OSError: return 'unknown'           # unclassifiable -- do not kill on it
    recorded=' '.join(str(recorded_birth or '').split())
    observed=birth(pid)
    if not recorded or not observed: return 'unknown'  # incomparable, never a kill
    return 'live' if recorded == observed else 'dead'  # mismatch = pid reuse
def verdict(row):
    try: pid=int(row.get('pid'))
    except (TypeError, ValueError): return 'dead'
    return proc_verdict(pid, row.get('pid_start_time') or row.get('pid_birth'))
def alive(row): return verdict(row) != 'dead'
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
      # D1-SINGLE-WRITER-FOR-LANE-STATE: a real worker adopting a lane OWNS
      # it again. The refresh carries a live pid, so any recovery placeholder
      # state on the row is over: clear the flag (this is exactly the
      # "recovered only via a REAL recovery" gate — adoption is one) and the
      # row's phase transitions re-open (the registry's update_phase refuses
      # rows with recovered=true).
      if existing.get('recovered'):
        existing['recovered']=False
        event(existing, 'unowned_row_adopted')
      if lead_pid: existing['lead_pid'] = int(lead_pid)
      if lead_pid_birth: existing['lead_pid_birth'] = lead_pid_birth
      event(existing, 'registered_refresh')
    else:
      # SD-DISPATCH-WRITESET-TWO-ROW-FIX-01 (F4s): this append is the second
      # same-task row shape. The registry engine recreates a row for a known
      # task by CARRYING writes/writes_reason/first_seen_at forward from the
      # previous row (leadv2-active-registry.sh register); this engine minted
      # a bare row instead, so an adopting runner whose original row was gone
      # silently became a live unknown-scope blocker for the pending window.
      # Same inheritance here, plus a refusal under lane_adopt_pid (the one
      # caller whose row is expected to already exist): no reusable row AND
      # no declaration to inherit means adoption cannot state the lane's
      # write set -- refuse BEFORE the yaml rewrite, never mint row shape B.
      prior=next((r for r in rows if r.get('task_id') == task), None)
      prior_writes=(prior.get('writes') if prior is not None else None) or (prior.get('write_set') if prior is not None else None)
      prior_reason=prior.get('writes_reason') if prior is not None else None
      if os.environ.get('LEADV2_LANE_STATE_ADOPT_STRICT','') == '1' and prior_writes is None and prior_reason is None:
        print('[lane-state] register task=%s refused: adoption found no reusable row and no write set or reason to inherit' % task, file=sys.stderr)
        sys.exit(4)
      row={'task_id':task, 'session_id':lead, 'lead_session_id':lead, 'worktree':worktree, 'phase':phase,
           'pid':pid, 'pid_start_time':birth(pid), 'started_at':now(), 'updated_at':now(), 'dead_at':None,
           'recovered':False, 'lane_events':[]}
      if prior_writes is not None:
        row['writes']=prior_writes
      elif prior_reason is not None:
        row['writes_reason']=prior_reason
      if prior is not None:
        row['first_seen_at']=prior.get('first_seen_at') or prior.get('started_at') or row['started_at']
        # Replace, never accumulate: a dead same-task tombstone left in place
        # SHADOWS the fresh row for every first-match reader (update_phase
        # refuses "row is closed" picking the tombstone) -- the registry
        # engine already removes-on-recreate; mirror it here.
        rows[:] = [r for r in rows if r.get('task_id') != task]
      if lead_pid: row['lead_pid'] = int(lead_pid)
      if lead_pid_birth: row['lead_pid_birth'] = lead_pid_birth
      event(row, 'registered'); rows.append(row)
  # elif op == 'transition': REMOVED (D1-SINGLE-WRITER-FOR-LANE-STATE).
  # Phase advances have exactly one writer: the registry's update_phase op
  # (leadv2-active-registry.sh), which now also refuses closed rows (rc=4)
  # and recovery-owned rows (rc=8) and stamps the same transition lane_event
  # with the detail payload. The lane_transition shell wrapper below routes
  # through it; this engine no longer patches phase at all.
  elif op == 'deregister':
    task, reason=args
    row=next((r for r in rows if r.get('task_id') == task and not r.get('dead_at')), None)
    if row:
      row['dead_at']=now(); row['updated_at']=now(); event(row, 'deregistered', reason)
      # WAVE0-LIB-SWALLOWS-ITS-OWN-FAILURE-01 (L-3): rc now says whether the
      # registry row was actually mutated. stdout is consumed by the count/
      # alive callers, so these lines go to stderr only.
      print('[lane-state] deregister task=%s matched=1' % task, file=sys.stderr)
    else:
      # No live row matched: exit 2 BEFORE the unconditional yaml rewrite
      # below, so deregistering an unknown or already-tombstoned task stops
      # rewriting active.yaml for nothing and says so instead of rc 0.
      # Op-scoped on purpose: reconcile/register keep their own contracts.
      print('[lane-state] deregister task=%s matched=0 reason=no_live_row' % task, file=sys.stderr)
      sys.exit(2)
  elif op == 'reconcile':
    root=args[0]
    # RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01 fix 3: an unowned
    # recovered row (registered WITHOUT a pid because ownership could not be
    # established) must neither be killed merely for being pidless (that
    # would let the next pass re-adopt a fresh bystander forever) nor block
    # the registry indefinitely (a writes-less row inside
    # _lv2_ws_pending refuses ANY concurrent dispatch). It ages out on a TTL.
    # The number mirrors LEADV2_WRITESET_PENDING_WINDOW_SEC (default 900s):
    # the registry can only refuse a dispatch on this row inside that window
    # anyway, so expiring here means the row can never block longer than it
    # could block, and observers keep 15 minutes of visibility.
    def unowned_expired(row):
        started=row.get('started_at')
        if not started: return True
        try:
            ts=datetime.datetime.strptime(started,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
        except ValueError: return True
        try: ttl=int(os.environ.get('LEADV2_RECOVERED_UNOWNED_TTL_SEC','900') or 900)
        except ValueError: ttl=900
        if ttl < 0: ttl=900
        return (datetime.datetime.now(datetime.timezone.utc)-ts).total_seconds() > ttl
    for row in rows:
      if row.get('dead_at'): continue
      if row.get('recovered') and not row.get('pid'):
        if unowned_expired(row):
          row['dead_at']=now(); row['updated_at']=now(); event(row, 'recovered_unowned_expired')
        continue
      if not alive(row):
        row['dead_at']=now(); row['updated_at']=now(); event(row, 'reconciled_dead')
    # D1-SINGLE-WRITER-FOR-LANE-STATE: the REAPER. Expiry above only marks
    # dead_at — expired recovered rows then accumulated forever (24 measured
    # live 2026-09-06, every one dead_at'd 2026-09-04, still rendering as
    # ПРИЗРАК ghosts in the pulse). A recovered row is REMOVED once it has
    # been dead longer than LEADV2_RECOVERED_UNOWNED_RETENTION_SEC (default
    # 86400s) — long enough for a human to see the ghost across a day of
    # pulses, short enough that unowned rows nobody owns and nothing closes
    # cannot fill the registry. reconcile is the single owner of the
    # recovered lifecycle, so it owns the reaping too. Normal (non-recovered)
    # tombstones are NOT reaped here — their pruning belongs to the
    # snapshot's tombstone+prune path, which also preserves history.
    def dead_age(row):
        dead=row.get('dead_at')
        if not dead: return -1
        try:
            ts=datetime.datetime.strptime(dead,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
        except ValueError: return -1
        return (datetime.datetime.now(datetime.timezone.utc)-ts).total_seconds()
    try: retention=int(os.environ.get('LEADV2_RECOVERED_UNOWNED_RETENTION_SEC','86400') or 86400)
    except ValueError: retention=86400
    if retention < 0: retention=86400
    reaped=[str(r.get('task_id')) for r in rows if r.get('recovered') and dead_age(r)>retention]
    if reaped:
      rows[:] = [r for r in rows if not (r.get('recovered') and dead_age(r)>retention)]
      print('recovered_rows_reaped=%s' % ','.join(reaped), file=sys.stderr)
    # THE-LANE-REGISTRY-ONLY-EVER-GROWS-01 (founder order 2026-09-13): a
    # finished lane must LEAVE the registry. reconcile already tombstones
    # dead rows (dead_at above) and reaps recovered rows, but a NORMAL
    # row's tombstone lived forever -- the only other prune path is the
    # retired supervisor's snapshot tombstone+prune, which nothing on the
    # single-lead live path runs with writes enabled. The founder pulse's
    # ghost count therefore only went up (3 -> 12 inside one session,
    # measured 2026-09-13). This reaper removes a tombstoned row ONLY on
    # evidence the lane's ending itself wrote -- the glm run dir's own
    # meta.yaml status, a dispatch-ledger terminal record, or a closed
    # backlog row -- never on a liveness observer's say-so (ps/pgrep,
    # pidfiles and active.yaml itself have each lied here; journal growth
    # plus meta.yaml have not) -- and NEVER while the lane journal is
    # still growing. LEADV2_REAP_NORMAL_ROWS=0 is the single-flip rollback.
    if os.environ.get('LEADV2_REAP_NORMAL_ROWS','1') != '0':
      import glob as _glob, json as _json, time as _time
      _now_epoch=_time.time()
      def _reap_sig(row):
        wt=str(row.get('worktree') or '')
        if '/.claude/worktrees/' in wt:
          return os.path.basename(wt.rstrip('/')) or str(row.get('task_id') or '')
        t=str(row.get('task_id') or '')
        return t[len('dispatch-'):] if t.startswith('dispatch-') else t
      _glm_root=os.environ.get('LEADV2_REAP_GLM_RUNS_DIR','') or os.path.join(os.path.expanduser('~'),'.claude','cache','glm-runs')
      try: _live_s=max(0,int(os.environ.get('LEADV2_REAP_LIVE_S','900') or 900))
      except ValueError: _live_s=900
      try: _grace_s=max(0,int(os.environ.get('LEADV2_REAP_GRACE_SEC','300') or 300))
      except ValueError: _grace_s=300
      def _glm_state(sig):
        # -> (terminal, journal_fresh, running) from the NEWEST run dir the
        # worker's own runner wrote. status complete|failed (or an exit_code
        # file) is the ending's own record; a journal.jsonl touched inside
        # the live window is a lane still writing, whatever status says;
        # status running is the worker itself saying it is alive.
        dirs=[d for d in _glob.glob(os.path.join(_glm_root,'*-'+sig+'-*')) if os.path.isdir(d)]
        if not dirs: return (False, False, False)
        newest=max(dirs, key=lambda d:(os.path.getmtime(d), d))
        st=''
        try:
          for ln in open(os.path.join(newest,'meta.yaml'),encoding='utf-8',errors='replace'):
            if ln.startswith('status:'): st=ln.split(':',1)[1].strip(); break
        except OSError: pass
        terminal=st in ('complete','failed') or os.path.exists(os.path.join(newest,'exit_code'))
        fresh=False
        for probe in (os.path.join(newest,'journal.jsonl'), newest):
          try:
            if _now_epoch-os.path.getmtime(probe)<=_live_s: fresh=True; break
          except OSError: pass
        return (terminal, fresh, st == 'running')
      _ledger=os.environ.get('LEADV2_REAP_DISPATCH_LEDGER','') or os.path.join(os.path.dirname(path),'dispatch-ledger.jsonl')
      _ledger_terminal=set()
      try:
        for ln in open(_ledger,encoding='utf-8',errors='replace'):
          try: rec=_json.loads(ln)
          except ValueError: continue
          _sig=str(rec.get('task_sig') or '')
          if _sig and rec.get('terminal'): _ledger_terminal.add(_sig)
      except OSError: pass
      # The open-backlog mirror (docs/tasks.yaml, projected from
      # v_work_items_current) lists OPEN work items only: a closed row
      # leaves it. A dispatched lane always comes from a backlog row, so
      # for a non-recovered row "sig absent from a non-empty mirror" is the
      # closed signal -- the one terminal leg that covers arms writing
      # nothing else (codex lanes leave no glm run dir and, on a turn-cap
      # death, no ledger entry either). An unreadable/empty mirror fails
      # OPEN: absence of the file is never "everything is closed".
      _tasks_yaml=os.environ.get('LEADV2_REAP_TASKS_YAML','') or os.path.join(root,'docs','tasks.yaml')
      _open_ids=set()
      try:
        for ln in open(_tasks_yaml,encoding='utf-8',errors='replace'):
          s=ln.strip()
          if s.startswith('- id:'): _open_ids.add(s.split(':',1)[1].strip())
      except OSError: pass
      def _backlog_closed(sig):
        return bool(_open_ids) and sig not in _open_ids
      _drop_ids=set(); _drop_sigs=[]
      for row in rows:
        if row.get('recovered'): continue      # the recovered reaper above owns these
        if dead_age(row)<_grace_s: continue    # -1 (no tombstone) or younger than grace
        sig=_reap_sig(row)
        terminal, fresh, running=_glm_state(sig)
        if fresh:                              # journal growth is life -- never evict
          continue
        if running:                            # the worker's own run dir says running -- never evict
          continue
        if terminal or sig in _ledger_terminal or _backlog_closed(sig):
          _drop_ids.add(id(row)); _drop_sigs.append(sig)
      if _drop_ids:
        # Row-identity, not sig-identity: e1fb1204 and dispatch-e1fb1204
        # share a sig, and a live sibling row under the same sig (kept by
        # the journal-fresh guard above) must survive its dead twin's reap.
        rows[:]=[r for r in rows if id(r) not in _drop_ids]
        print('finished_rows_reaped=%s' % ','.join(sorted(set(_drop_sigs))), file=sys.stderr)
    fixture_wt=os.environ.get('LEADV2_LANE_STATE_TEST_WORKTREES_FILE','')
    try:
      wt=open(fixture_wt, encoding='utf-8').read() if fixture_wt else subprocess.run(['git','-C',root,'worktree','list','--porcelain'], text=True, capture_output=True, timeout=5).stdout
      worktrees=[x[9:] for x in wt.splitlines() if x.startswith('worktree ')]
    except Exception: worktrees=[]
    known={os.path.realpath(str(r.get('worktree') or '')) for r in rows}
    # RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01 fix 1: a live row already
    # owns this lane when its task_id equals the lane worktree's basename
    # (the same identity recovery itself assigns). A LEAD-owner row carries
    # the REPO ROOT in worktree:, so a realpath-of-worktree set alone never
    # contains the lane and the lane was re-registered every pass. The
    # task_id match cannot be spoofed by a lead row pointing at the repo
    # root for an UNRELATED task (different task_id), and it must be ALIVE
    # (os.kill + birth match), so a dead lead row cannot suppress recovery.
    live_tasks={str(r.get('task_id')) for r in rows if not r.get('dead_at') and alive(r)}
    def proc_cwd(pid):
        # Test seam pairs with LEADV2_LANE_STATE_TEST_PS_FILE/BIRTH_FILE.
        fixture=os.environ.get('LEADV2_LANE_STATE_TEST_CWD_FILE','')
        if fixture:
            try:
                for line in open(fixture, encoding='utf-8'):
                    key, value=line.rstrip('\n').split('\t', 1)
                    if key == str(pid): return ' '.join(value.split())
            except OSError: pass
        try:
            out=subprocess.run(['lsof','-a','-p',str(pid),'-d','cwd','-Fn'], text=True, capture_output=True, timeout=3).stdout
            for l in out.splitlines():
                if l.startswith('n'): return l[1:]
        except Exception: pass
        return ''
    # ORPHAN (66d6209a) union 2026-09-04: argv classification alongside the
    # cwd probe. worker_markers = the programs a lane worker actually runs
    # under; non_workers = observation/tooling whose argv may mention a lane
    # path without owning the lane. Used below: any non_workers member in a
    # command blocks ADOPTION, a command made ONLY of non_workers does not
    # even count as a mention (no unowned visibility row for grep/tail/ps).
    ancestors=ancestry()
    worker_markers={'claude','leadv2-session-runner.sh','leadv2-codex-session-runner.sh','codex','glm-coder.sh','kimi-coder.sh'}
    non_workers={'leadv2-dispatch-code.sh','leadv2-lane-liveness.sh','grep','ps','tail','Monitor'}
    for worktree in worktrees:
      real=os.path.realpath(worktree)
      if '/.claude/worktrees/' not in real: continue
      task=os.path.basename(real)
      if real in known or task in live_tasks: continue
      fixture=os.environ.get('LEADV2_LANE_STATE_TEST_PS_FILE','')
      try:
        ps=open(fixture, encoding='utf-8').read().splitlines() if fixture else subprocess.run(['ps','-axo','pid=,lstart=,command='], text=True, capture_output=True, timeout=3).stdout.splitlines()
      except Exception: ps=[]
      # RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01 fix 2 + ORPHAN (66d6209a)
      # union 2026-09-04: substring over `ps` is not ownership. A pid is
      # adopted only when it is a worker-marker program (never observation
      # tooling, never this reconcile's own ancestry) that either RUNS IN the
      # lane (cwd is the worktree) or was INVOKED WITH the lane (the worktree
      # is a whole argv token). A bystander whose argv merely MENTIONS the
      # path (a tool shell, a grep, this reconcile itself) is neither.
      # Neither proof available -> no adoption (fail to pid-less, never to a
      # wrong pid). start == birth(pid) stays the pid-recycling guard.
      adopted=None; mentioned=False
      for line in ps:
        if worktree not in line: continue
        parts=line.strip().split(None, 6)
        if len(parts) < 7: continue
        pid=int(parts[0]); start=' '.join(parts[1:6]); command=parts[6]
        try: argv=shlex.split(command)
        except ValueError: continue
        # ORPHAN (66d6209a) union: a whole argv token (or parent dir), never
        # a substring -- X-old is not X.
        token=any(arg == worktree or arg.startswith(worktree + '/') for arg in argv)
        programs={os.path.basename(arg) for arg in argv}
        # Mention (-> unowned visibility row) needs a token hit from a command
        # whose LEAD program (argv[0]) is not observation tooling: grep/tail/
        # ps/dispatch never make a lane (branch a/b/c); a tool shell that
        # names the lane does (HEAD case 2). argv[0] decides, not any token:
        # flags and the lane path itself would otherwise pollute the class.
        argv0=os.path.basename(argv[0]) if argv else ''
        if token and argv0 not in non_workers: mentioned=True
        if pid in ancestors: continue
        if programs & non_workers: continue
        if not programs & worker_markers: continue
        cwd_owner = os.path.realpath(proc_cwd(pid) or '') == real
        if pid > 1 and start == birth(pid) and (token or cwd_owner):
          adopted=(pid,start); break
      if not mentioned: continue
      if adopted:
        row={'task_id':task, 'session_id':'recovered', 'lead_session_id':'recovered', 'worktree':worktree,
             'phase':'recovered', 'pid':adopted[0], 'pid_start_time':adopted[1], 'started_at':now(), 'updated_at':now(),
             'dead_at':None, 'recovered':True, 'lane_events':[]}
        event(row, 'recovered_orphan')
      else:
        # Registered WITHOUT a pid: visibility row for the status surface /
        # humans; it does not claim an owner, and it ages out on
        # LEADV2_RECOVERED_UNOWNED_TTL_SEC (see fix 3 above) so it cannot
        # block dispatch beyond the registry's own pending window.
        row={'task_id':task, 'session_id':'recovered', 'lead_session_id':'recovered', 'worktree':worktree,
             'phase':'recovered_unowned', 'started_at':now(), 'updated_at':now(),
             'dead_at':None, 'recovered':True, 'lane_events':[]}
        event(row, 'recovered_unowned_no_pid')
      rows.append(row); known.add(real)
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
    # LANE-ALIVE-PREDICATE-CALLS-A-LIVE-LANE-DEAD-01: routes through
    # proc_verdict, so EPERM counts as live and an unobservable birth on
    # either side degrades to unknown (exit 0) instead of dead.
    lead=args[0]
    row=next((r for r in rows if r.get('lead_session_id') == lead and r.get('lead_pid')), None)
    if row is None: sys.exit(1)
    try: lp=int(row.get('lead_pid'))
    except (TypeError, ValueError): sys.exit(1)
    sys.exit(0 if proc_verdict(lp, row.get('lead_pid_birth')) != 'dead' else 1)
  if op == 'reconcile':
    # THE-LANE-REGISTRY-ONLY-EVER-GROWS-01: rendered_at must mean something.
    # It used to be stamped only by render_index (a lazy, read-side render),
    # so it trailed wall time by hours while dead rows accumulated -- an
    # hour-stale timestamp presented as current. reconcile is the periodic
    # sweep (SessionStart hook + every dispatch), so every sweep restamps
    # it: the value now reads "registry last swept/mutated", and a stale
    # value honestly names a sweep that did not run.
    data.setdefault('meta', {})['rendered_at']=now()
  fd,tmp=tempfile.mkstemp(prefix='.active.yaml.', dir=os.path.dirname(path))
  with os.fdopen(fd,'w',encoding='utf-8') as f: yaml.safe_dump(data,f,default_flow_style=False,sort_keys=False)
  os.replace(tmp,path)
PY
}
lane_register() { _lv2_lane_state_mutate register "$1" "$2" "$3" "$4" "${5:-$$}" "${6:-}" "${7:-}"; }
lane_transition() { # <task-id> <phase> [detail]
  # D1-SINGLE-WRITER-FOR-LANE-STATE: phase advances have ONE owner — the
  # registry's update_phase op. This wrapper routes through it (lazy-sourcing
  # the registry from this lib's own scripts/ dir) and keeps the wrapper's rc
  # contract a superset of the old op's: 4 = row missing or closed (the old
  # op returned 4 only for missing), 8 = refused because the row is
  # recovery-owned, 9 = registry could not be loaded at all.
  local _lt_rc=0 _lt_flags _lt_pf=0
  _lt_flags="$-"
  if [[ -o pipefail ]]; then _lt_pf=1; fi
  if ! declare -F _leadv2_active_registry_loaded >/dev/null 2>&1; then
    source "${_lv2_lane_state_dir}/leadv2-active-registry.sh" >/dev/null 2>&1 || _lt_rc=9
    # The registry restores the caller's options on its own, but its
    # root_error EARLY-RETURN path aborts the source before the EOF restore;
    # belt-and-braces, put the shell back exactly as we found it.
    if [[ "$_lt_flags" != *e* ]]; then set +e; fi
    if [[ "$_lt_flags" != *u* ]]; then set +u; fi
    if [[ "$_lt_pf" -eq 0 ]]; then set +o pipefail; fi
  fi
  if [[ "$_lt_rc" -ne 0 ]]; then
    printf -- '[lane-state] lane_transition: registry unavailable — phase write refused\n' >&2
    return "$_lt_rc"
  fi
  LEADV2_PROJECT_ROOT="$(_lv2_lane_state_root)" leadv2_active_update_phase "$1" "$2" "-" "${3:-}"
}
lane_deregister() { _lv2_lane_state_mutate deregister "$1" "${2:-closed}"; }
lane_alive() { _lv2_lane_state_mutate alive "$1"; }
lane_lead_alive() { _lv2_lane_state_mutate lead_alive "$1"; }
lane_reconcile() { _lv2_lane_state_mutate reconcile "$(_lv2_lane_state_root)"; }
lane_count_live() { _lv2_lane_state_mutate count "$1"; }
lane_adopt_pid() { # <task-id> <lead-session-id> <worktree> <phase> <worker-pid>
  # SD-DISPATCH-WRITESET-TWO-ROW-FIX-01 (F4s): adoption is the one lane_register
  # caller whose row is expected to already exist -- dispatch registered it
  # (writes_reason=prepass_pending, then the resolved declaration). Flag the
  # register call strict so that when the original row is gone the engine
  # REFUSES to mint a write-less row (rc 4) instead of silently creating an
  # unknown-scope live blocker. Plain lane_register callers keep the legacy
  # append behavior byte-for-byte.
  LEADV2_LANE_STATE_ADOPT_STRICT=1 lane_register "$1" "$2" "$3" "$4" "$5" || return $?
  lane_transition "$1" "$4" "worker_pid_adopted"
}
