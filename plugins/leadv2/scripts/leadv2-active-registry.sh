#!/usr/bin/env bash
# leadv2-active-registry.sh — CRUD operations on docs/leadv2/active.yaml
# Source this file; do not exec directly.
#
# Functions:
#   leadv2_active_register <task_id> <class> <worktree> <branch> <daemon_mode>
#                           [<group_key>] [<risk_tags>] [<writes>]  (LANE-WRITESET-REGISTRY-01)
#   leadv2_active_unregister <task_id>
#   leadv2_active_update_phase <task_id> <phase> [<resolved_model>]
#   leadv2_active_update_pulse <task_id>
#   leadv2_active_heartbeat <task_id> <checkpoint>              (PULSE-01)
#   leadv2_active_mark_finished <task_id> <outcome> [<evidence_json>]  (PULSE-01)
#   leadv2_active_set_writes <task_id> <writes_csv>              (SUPERVISOR-AUDIT-01 T-E)
#   leadv2_active_set_attempt <task_id> <attempt_id>              (SD-LEDGER-SWEEP-HARDEN-01)
#   leadv2_active_set_worker_pid <task_id> <pid> <pid_birth>      (LANE-REGISTRY-SELF-DEADLOCK-01)
#   leadv2_active_render_index
#   leadv2_active_list
#   leadv2_active_check_limits <class>
#
# All YAML writes use Python flock + atomic temp-file (same pattern as
# _leadv2_active_py_lock in leadv2-helpers.sh).
#
# Exit codes for leadv2_active_check_limits:
#   0 — OK
#   1 — hard_limit_reached
#   2 — heavy_conflict
#   3 — budget_refused
#
# Exit codes for leadv2_active_register's `writes` admission check
# (LANE-WRITESET-REGISTRY-01, D3/D7 -- fires only when a non-empty `writes`
# is passed; folded into the SAME flock as the append, so admission is
# atomic):
#   5 — writeset_conflict (real intersection with an alive lane's writes)
#   6 — writeset_unknown (an alive incumbent has no `writes`/`write_set` at
#       all, and LEADV2_WRITESET_ENFORCE=block; under the default `warn` this
#       admits and prints LEADV2_WRITESET_UNKNOWN instead)
#
# fix-round-1 H1: an incumbent with no writes yet but still inside its own
# LEADV2_WRITESET_PENDING_WINDOW_SEC (default 900s) since `started_at` is
# treated as rc=5 unconditionally, not rc=6/warn -- see _lv2_ws_pending().
# This closes the TOCTOU where dispatch-code.sh registers a row before the
# architect prepass has resolved its writes, then patches the same row once
# known (dispatch-code.sh:~5859 and :~6005).

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────
# B1 fail-closed root resolution (SUPERVISE-V2-01 item 2), same order as
# leadv2-supervise.sh: LEADV2_PROJECT_ROOT -> CLAUDE_PROJECT_DIR -> git
# toplevel of cwd. NEVER a bare ambient `$PROJECT_ROOT`/`$(pwd)` fallback —
# an unrelated garbage PROJECT_ROOT env var must not be trusted silently.
if [[ -n "${LEADV2_PROJECT_ROOT:-}" ]]; then
  :
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  LEADV2_PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
elif _lv2ar_top="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null)"; then
  LEADV2_PROJECT_ROOT="$_lv2ar_top"
else
  printf -- '[leadv2-active-registry] root_error: could not resolve project root — set LEADV2_PROJECT_ROOT or CLAUDE_PROJECT_DIR, or run from inside a git worktree (cwd=%s)\n' "$(pwd)" >&2
  return 1 2>/dev/null || exit 1
fi

# LEAD-CONTROL-PLANE-01: active.yaml is a cross-worktree registry — every
# /leadv2 session runs in its own `git worktree add` checkout, so a
# repo-relative docs/leadv2/active.yaml gave each session a PRIVATE copy
# (registry saw only itself). Resolved via scripts/leadv2-state-path.sh,
# which uses `git rev-parse --git-common-dir` — identical from every
# worktree of the same repo.
_leadv2_state_path_sh() {
  local bundled
  # The registry can be sourced while operating on a different repository
  # (ephemeral-root consolidation is exactly that case).  Resolve the helper
  # from this loaded plugin first; deriving it from the target project writes
  # a private docs/leadv2/active.yaml when that project has no scripts copy.
  if [[ -n "${LEADV2_STATE_PATH_BIN:-}" && -x "${LEADV2_STATE_PATH_BIN}" ]]; then
    printf -- '%s' "${LEADV2_STATE_PATH_BIN}"
    return 0
  fi
  bundled="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-state-path.sh"
  if [[ -x "${bundled}" ]]; then
    printf -- '%s' "${bundled}"
  else
    printf -- '%s/scripts/leadv2-state-path.sh' "${LEADV2_PROJECT_ROOT}"
  fi
}

_leadv2_yaml_file() {
  local resolver
  resolver="$(_leadv2_state_path_sh)"
  if [[ -x "$resolver" ]]; then
    PROJECT_ROOT="${LEADV2_PROJECT_ROOT}" "$resolver" active.yaml
  else
    printf -- '%s/docs/leadv2/active.yaml' "${LEADV2_PROJECT_ROOT}"
  fi
}

_leadv2_yaml_lockfile() {
  local resolver
  resolver="$(_leadv2_state_path_sh)"
  if [[ -x "$resolver" ]]; then
    PROJECT_ROOT="${LEADV2_PROJECT_ROOT}" "$resolver" active.yaml.lock
  else
    printf -- '%s/docs/leadv2/active.yaml.lock' "${LEADV2_PROJECT_ROOT}"
  fi
}

_leadv2_state_md() {
  printf -- '%s/docs/LEAD_V2_STATE.md' "${LEADV2_PROJECT_ROOT}"
}

# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 round 6: an interrupted/sandboxed
# launcher can leave an otherwise real leadv2 lane in
# <state-base>/.ephemeral/leadv2-lwt.*/active.yaml.  Those roots are useful
# for scratch repos, but they are not a second production control plane: the
# founder board reads the durable <state-base>/leadv2 registry.  Consolidate
# only rows whose declared worktree belongs to THIS repository's git common
# dir; a foreign scratch repository is never imported merely because it uses
# the same state base.
_leadv2_canonical_yaml_file() {
  local resolver
  resolver="$(_leadv2_state_path_sh)"
  if [[ -x "$resolver" ]]; then
    LEADV2_STATE_ROOT= PROJECT_ROOT="${LEADV2_PROJECT_ROOT}" "$resolver" --no-link active.yaml
  else
    printf -- '%s/docs/leadv2/active.yaml' "${LEADV2_PROJECT_ROOT}"
  fi
}

leadv2_active_consolidate_ephemeral_roots() {
  local common_dir state_base canonical lockfile source_root source_yaml source_common
  common_dir="$(git -C "${LEADV2_PROJECT_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ -n "$common_dir" ]] || return 0
  # Scratch fixtures intentionally use ephemeral state.  A remote or the
  # project marker is the same real-repository predicate as state-path.sh.
  if ! { git -C "${LEADV2_PROJECT_ROOT}" remote 2>/dev/null | grep -q . \
      || [[ -f "${LEADV2_PROJECT_ROOT}/REAL-REPO" || -f "${LEADV2_PROJECT_ROOT}/.git/leadv2-real-repo-marker" ]]; }; then
    return 0
  fi
  state_base="${LEADV2_STATE_BASE:-${HOME}/.claude/leadv2-state}"
  [[ -d "${state_base}/.ephemeral" ]] || return 0
  canonical="$(_leadv2_canonical_yaml_file)"
  lockfile="${canonical}.lock"
  mkdir -p "$(dirname "${canonical}")" 2>/dev/null || return 0
  [[ -f "${canonical}" ]] || printf 'sessions: []\n' > "${canonical}" 2>/dev/null || return 0

  for source_root in "${state_base}/.ephemeral"/*; do
    [[ -d "${source_root}" ]] || continue
    source_yaml="${source_root}/active.yaml"
    [[ -f "${source_yaml}" ]] || continue
    python3 - "${source_yaml}" "${canonical}" "${lockfile}" "${common_dir}" <<'PYEOF'
import fcntl, os, sys, tempfile
try:
    import yaml
except Exception:
    sys.exit(0)

source, target, lock_path, expected_common = sys.argv[1:]
try:
    with open(source, encoding="utf-8") as fh:
        incoming = yaml.safe_load(fh) or {}
except Exception:
    sys.exit(0)

def belongs_here(row):
    worktree = row.get("worktree") if isinstance(row, dict) else None
    if not isinstance(worktree, str) or not worktree:
        return False
    import subprocess
    try:
        got = subprocess.check_output(
            ["git", "-C", worktree, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            stderr=subprocess.DEVNULL, text=True).strip()
        return got == expected_common
    except Exception:
        return False

rows = [r for r in (incoming.get("sessions") or []) if belongs_here(r)]
if not rows:
    sys.exit(0)
os.makedirs(os.path.dirname(lock_path), exist_ok=True)
with open(lock_path, "a+") as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    try:
        with open(target, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
    except Exception:
        doc = {}
    existing = [r for r in (doc.get("sessions") or []) if isinstance(r, dict)]
    by_task = {str(r.get("task_id")): i for i, r in enumerate(existing) if r.get("task_id")}
    changed = False
    for row in rows:
        tid = str(row.get("task_id"))
        pos = by_task.get(tid)
        if pos is None:
            existing.append(row)
            by_task[tid] = len(existing) - 1
            changed = True
        elif str(row.get("last_pulse_at") or "") > str(existing[pos].get("last_pulse_at") or ""):
            existing[pos] = row
            changed = True
    if changed:
        doc["sessions"] = existing
        fd, tmp = tempfile.mkstemp(prefix=".active.yaml.consolidate.", dir=os.path.dirname(target))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                yaml.safe_dump(doc, fh, default_flow_style=False, sort_keys=False)
            os.replace(tmp, target)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
PYEOF
  done
}

# ── Core Python flock + atomic-write helper ───────────────────────────────
# _leadv2_yaml_py_lock <lockfile> <yaml_file> <op> [args...]
#
# ops: register   <session_id> <task_id> <worktree> <branch> <started_at>
#                 <phase> <class> <pid> <pid_birth> <parent_session_id>
#                 <daemon_mode> <last_pulse_at> <pulse_log>
#      unregister <task_id>
#      update_phase <task_id> <phase> [<resolved_model>]
#      update_pulse <task_id> <ts>
#      mark_stale  <task_id>
#      append_provider_receipt <task_id> <receipt_json>
#      set_writes  <task_id> <writes_csv>          (SUPERVISOR-AUDIT-01 T-E)
#      read        → writes YAML to stdout (no mutation)
#
_leadv2_yaml_py_lock() {
  python3 - "$@" <<'PYEOF'
import sys, os, fcntl, tempfile, datetime, json
try:
    import yaml
except ImportError:
    print("[registry] PyYAML not found; install pyyaml", file=sys.stderr)
    sys.exit(1)

def _now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

lockfile_path = sys.argv[1]
yaml_path     = sys.argv[2]
op            = sys.argv[3]
args          = sys.argv[4:]

INITIAL = {
    "meta": {
        "schema_version": 2,
        "rendered_at": "",
        "hard_limit": 3,
        # HEAVY-MAX-2-WITH-COLLISION-GUARD-01: heavy_max is now the SOLE
        # control for concurrent Heavy/strategic lanes. heavy_strategic_solo
        # is kept (default False) purely as an explicit kill-switch a founder
        # can flip True to force serialize; legacy active.yaml files written
        # before this change (no heavy_max key at all) still fall back to the
        # old True default at read time -- see leadv2_active_check_limits().
        "heavy_max": 3,
        "heavy_strategic_solo": False,
        "light_max": 3,
        "standard_max": 2,
    },
    "sessions": [],
}

def _pid_alive(pid_val) -> bool:
    try:
        pid = int(pid_val)
        os.kill(pid, 0)
        return True
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        return False

# LANE-WRITESET-REGISTRY-01: shared prefix-overlap predicate, copied from
# leadv2-writes-overlap.sh:86-89 (that script is frozen/off-limits, D4) --
# used by both the `register` op's admission intersect and the read-only
# `check_writes` op the commit-time drift check (D5/D6) calls.
def _lv2_ws_norm(csv):
    out = []
    for p in csv.split(","):
        p = p.strip()
        if p:
            out.append(os.path.normpath(p))
    return out

def _lv2_ws_overlaps(a, b):
    if a == b:
        return True
    return (b + os.sep).startswith(a + os.sep) or (a + os.sep).startswith(b + os.sep)

# LANE-WRITESET-REGISTRY-01 fix-round-1 H1: a row that is alive but has not
# yet had its writes persisted is `unknown` under D7 -- but a LEGACY row
# (registered before this feature existed, or one whose lane genuinely
# declares no writes) and a row mid-resolution (dispatch-code.sh registers
# self BEFORE the architect prepass fills lane_writes, then patches the same
# row once it's known -- see dispatch-code.sh:5859/:6005) are not the same
# risk. A legacy row is stable forever; a mid-resolution row is a live TOCTOU
# window that closes itself within one prepass cycle. Treat only the latter
# as blocking, regardless of LEADV2_WRITESET_ENFORCE, so the common
# concurrent-dispatch race (two lanes registering while one is still in
# prepass) is refused even under the default `warn` soak.
# M5: a dead-PID incumbent that has not yet been swept `stale` must not
# block admission indefinitely -- _pid_alive is already used one section
# below (the refresh_existing branch) for exactly this liveness question.
# Only skip on an actually-recorded, actually-dead pid; a row with no pid
# recorded is not assumed dead.
def _lv2_ws_dead(other):
    pid = other.get("pid")
    return pid is not None and not _pid_alive(pid)

def _lv2_ws_pending(other):
    started = other.get("started_at")
    if not started:
        return False
    try:
        ts = datetime.datetime.strptime(started, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc
        )
    except ValueError:
        return False
    window = int(os.environ.get("LEADV2_WRITESET_PENDING_WINDOW_SEC", "900") or "900")
    age = (datetime.datetime.now(datetime.timezone.utc) - ts).total_seconds()
    return 0 <= age <= window

os.makedirs(os.path.dirname(lockfile_path), exist_ok=True)
lock_fd = open(lockfile_path, "a+")
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX)

    # Ensure yaml file exists
    os.makedirs(os.path.dirname(yaml_path), exist_ok=True)
    if not os.path.exists(yaml_path):
        with open(yaml_path, "w", encoding="utf-8") as fh:
            yaml.dump(INITIAL, fh, default_flow_style=False, sort_keys=False)

    with open(yaml_path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}

    if "meta" not in data:
        data["meta"] = INITIAL["meta"].copy()
    if "sessions" not in data or data["sessions"] is None:
        data["sessions"] = []

    sessions = data["sessions"]

    if op == "read":
        yaml.dump(data, sys.stdout, default_flow_style=False, sort_keys=False)
        sys.exit(0)

    elif op == "register":
        (session_id, task_id, worktree, branch, started_at,
         phase, cls, pid, pid_birth, parent_session_id,
         daemon_mode, last_pulse_at, pulse_log, group_key, risk_tags,
         writes) = args
        group_key = None if group_key in ("", "null", "None", "-") else group_key
        risk_tags = None if risk_tags in ("", "null", "None", "-") else risk_tags
        writes = None if writes in ("", "null", "None", "-") else writes

        pid_int = int(pid) if pid not in ("null", "", "None") else None
        daemon_bool = daemon_mode.lower() in ("1", "true", "yes")

        # LANE-WRITESET-REGISTRY-01 D3: intersect the candidate's declared
        # `writes` against every non-stale OTHER row's writes, BEFORE the
        # append/refresh below, inside this SAME flock. A shell-level
        # check-then-register is a TOCTOU race under CONCURRENCY-2-LANES-01
        # (two leads, two sessions, both read no-conflict, both register).
        # D2: an empty candidate writes gets no judgement here -- dispatch's
        # REQUIRE_LANE_WRITES already fail-closes that case upstream.
        if writes:
            enforce = os.environ.get("LEADV2_WRITESET_ENFORCE", "warn")
            cand_paths = _lv2_ws_norm(writes)
            for other in sessions:
                if other.get("task_id") == task_id or other.get("stale") or _lv2_ws_dead(other):
                    continue
                # D1: writer only ever writes `writes`; reader unions the
                # `write_set` alias for forward tolerance with any writer
                # that still uses that name.
                other_raw = other.get("writes")
                if other_raw is None:
                    other_raw = other.get("write_set")
                if other_raw is None:
                    # H1 fix-round-1: a row still inside its own registration
                    # window (mid architect-prepass, writes not yet patched
                    # in) is refused unconditionally -- this is the TOCTOU
                    # the two-phase dispatch-code.sh registration reopens
                    # otherwise. Checked BEFORE the D7 unknown/enforce split
                    # below, which remains the policy for genuinely legacy
                    # rows outside the pending window.
                    if _lv2_ws_pending(other):
                        print(f"[registry] writeset conflict: other={other.get('task_id')} reason=pending_resolution", file=sys.stderr)
                        sys.exit(5)
                    # D7: an incumbent with neither key is the third state,
                    # `unknown` -- never silently "conflicts with everything"
                    # nor "conflicts with nothing".
                    if enforce == "block":
                        print(f"[registry] writeset unknown: other={other.get('task_id')}", file=sys.stderr)
                        sys.exit(6)
                    # M6: stderr, like the conflict/pending-conflict messages
                    # above -- the documented stdout contract of `register`
                    # is "session_id" only (registry.sh:~690).
                    print(f"LEADV2_WRITESET_UNKNOWN other={other.get('task_id')}", file=sys.stderr)
                    continue
                if isinstance(other_raw, (list, tuple)):
                    other_csv = ",".join(str(w) for w in other_raw)
                else:
                    other_csv = str(other_raw)
                other_paths = _lv2_ws_norm(other_csv)
                if not other_paths:
                    continue
                hit = sorted({a for a in cand_paths for b in other_paths if _lv2_ws_overlaps(a, b)})
                if hit:
                    print(f"[registry] writeset conflict: other={other.get('task_id')} paths={','.join(hit)}", file=sys.stderr)
                    sys.exit(5)

        # Replace stale row for same task_id if PID is dead. A fanout launch
        # pre-registers the runner against the main checkout; when Gate 1 later
        # registers from the real task worktree, refresh ownership metadata but
        # preserve the live runner PID/provider receipts instead of appending a
        # duplicate or leaving a false main-worktree claim.
        existing = next((s for s in sessions if s.get("task_id") == task_id), None)
        refresh_existing = False
        if existing:
            if _pid_alive(existing.get("pid")):
                refresh_existing = True
                existing["worktree"] = worktree
                existing["branch"] = branch
                existing["class"] = cls
                existing["pulse_log"] = pulse_log
                existing["log_path"] = existing.get("log_path") or pulse_log
                existing["last_pulse_at"] = last_pulse_at
                existing["updated_at"] = _now_iso()
                existing["stale"] = False
                if writes is not None:
                    existing["writes"] = writes
                print(existing.get("session_id") or session_id)
            else:
                sessions.remove(existing)

        if not refresh_existing:
            now = _now_iso()
            sessions.append({
                "session_id": session_id,
                "task_id": task_id,
                "worktree": worktree,
                "branch": branch,
                "started_at": started_at,
                "phase": phase,
                "class": cls,
                "pulse_log": pulse_log,
                "pid": pid_int,
                "pid_birth": pid_birth,
                # LANE-REGISTRY-SELF-DEADLOCK-01: label WHO the row's `pid`
                # belongs to at register time (always the durable lead session
                # here). The post-spawn set_worker_pid op later flips this to
                # "worker" atomically with worker_pid/worker_pid_birth, so
                # leadv2-lane-liveness.sh can stop trusting a lead pid as
                # lane-liveness evidence. refresh_existing deliberately does
                # NOT set this -- refreshing must never relabel a row a fanout
                # runner owns (design §5.1/R3).
                "pid_role": "lead_durable",
                "parent_session_id": None if parent_session_id in ("null", "", "None") else parent_session_id,
                "daemon_mode": daemon_bool,
                "last_pulse_at": last_pulse_at,
                "stale": False,
                "note": "",
                # HEAVY-MAX-2-WITH-COLLISION-GUARD-01 (F1): a co-running
                # fanout's collision guard reads these live off a session row
                # -- this is the SECOND active.yaml writer (leadv2-fanout.sh's
                # own _fanout_register_session is the first); both must
                # persist group_key/risk_tags or the collision check is blind
                # to sessions registered through this path (Gate1 self-reg).
                "group_key": group_key,
                "risk_tags": risk_tags,
                "writes": writes,
                # D-d registry-honesty fields (SUPERVISE-V2-01 item 3) — additive,
                # every new row registers V2 explicitly; legacy rows written by
                # an older registry simply lack these keys (reader-side infers
                # protocol_version: 1 for those — see leadv2-supervise.sh).
                "protocol_version": 2,
                "backend": "headless" if daemon_bool else "terminal",
                "phase_started_at": started_at,
                "updated_at": now,
                "tmux_window": None,
                "tmux_pane": None,
                "log_path": pulse_log,
                "provider_receipts": [],
            })
            # Return session_id on stdout
            print(session_id)

    elif op == "check_writes":
        # LANE-WRITESET-REGISTRY-01 D5/D6: read-only re-check of a candidate
        # writes CSV against every non-stale OTHER row -- used by the
        # commit-time drift check to decide WARN vs BLOCK on undeclared
        # paths, WITHOUT persisting anything (never touches `data`/`sessions`).
        check_task_id, check_writes_csv = args
        enforce = os.environ.get("LEADV2_WRITESET_ENFORCE", "warn")
        if check_writes_csv:
            cand_paths = _lv2_ws_norm(check_writes_csv)
            for other in sessions:
                if other.get("task_id") == check_task_id or other.get("stale") or _lv2_ws_dead(other):
                    continue
                other_raw = other.get("writes")
                if other_raw is None:
                    other_raw = other.get("write_set")
                if other_raw is None:
                    if enforce == "block":
                        sys.exit(6)
                    continue
                if isinstance(other_raw, (list, tuple)):
                    other_csv = ",".join(str(w) for w in other_raw)
                else:
                    other_csv = str(other_raw)
                other_paths = _lv2_ws_norm(other_csv)
                if not other_paths:
                    continue
                hit = sorted({a for a in cand_paths for b in other_paths if _lv2_ws_overlaps(a, b)})
                if hit:
                    print(f"[registry] writeset conflict: other={other.get('task_id')} paths={','.join(hit)}", file=sys.stderr)
                    sys.exit(5)
        sys.exit(0)

    elif op == "unregister":
        task_id = args[0]
        data["sessions"] = [s for s in sessions if s.get("task_id") != task_id]

    elif op == "set_worktree":
        task_id, worktree = args
        row = next((s for s in sessions if s.get("task_id") == task_id), None)
        if row is None:
            # A launcher can resolve its lane before its direct fanout
            # registration has committed. Treat that ordering race as a
            # harmless no-op; the post-register retry supplies the value.
            sys.exit(0)
        row["worktree"] = worktree
        row["updated_at"] = _now_iso()

    elif op == "update_phase":
        # Accepts legacy 1-arg (phase only — task_id resolved by the bash
        # wrapper from $LEADV2_TASK_ID before invoking this python core) and
        # V2 2-arg (task_id, phase) forms; by the time control reaches here
        # both have already been normalized to 2 args by the caller.
        task_id, new_phase = args[0], args[1]
        # SUPERVISOR-AUDIT-01 phase-stamps addendum (founder 2026-07-30, model-stamp
        # extension): optional 3rd arg is the RESOLVED router arm at worker-launch --
        # the row's lead_model otherwise keeps fanout's pre-routing classifier guess
        # forever (statusline reads sessions[].lead_model, leadv2-lane-status-line-
        # tail.sh:277), which lies once the router picks a different arm. "" / "-" /
        # absent means "no change" -- every pre-existing 2-arg caller is a no-op here.
        new_model = args[2] if len(args) > 2 else ""
        now = _now_iso()
        for s in sessions:
            if s.get("task_id") == task_id:
                # phase_started_at is atomic WITH a real phase change only —
                # a heartbeat (update_pulse) never touches it, and calling
                # update_phase again with the SAME phase is a no-op on the
                # timestamp (idempotent re-entry, e.g. a retried hook call).
                if s.get("phase") != new_phase:
                    s["phase_started_at"] = now
                s["phase"] = new_phase
                if new_model not in ("", "-", "null", "None"):
                    s["lead_model"] = new_model
                s["updated_at"] = now
                break

    elif op == "update_pulse":
        task_id, ts = args
        for s in sessions:
            if s.get("task_id") == task_id:
                s["last_pulse_at"] = ts
                s["updated_at"] = ts
                break

    elif op == "update_pid":
        task_id, pid_str = args
        pid_int = int(pid_str) if pid_str not in ("null", "", "None") else None
        for s in sessions:
            if s.get("task_id") == task_id:
                s["pid"] = pid_int
                s["updated_at"] = _now_iso()
                break

    elif op == "mark_stale":
        task_id = args[0]
        for s in sessions:
            if s.get("task_id") == task_id:
                s["stale"] = True
                s["updated_at"] = _now_iso()
                break

    # PULSE-01: durable per-task heartbeat. Written by ANY arm (Sonnet
    # subagent, Codex/GLM job wrapper) at a low cadence -- NOT per-tool-call
    # (leadv2-pulse-json.sh's <50ms/no-python3 hot-path budget forbids a
    # flock+python write on every tool call; that hook keeps writing its own
    # local pulse.json, and a caller reconciles it into here occasionally).
    # heartbeat_checkpoint is bounded so a runaway caller can't bloat the
    # registry; last_pulse_at is the SAME field the (until now unused)
    # update_pulse op already wrote, so an old row upgrades in place.
    elif op == "heartbeat":
        task_id, ts, checkpoint = args
        checkpoint = (checkpoint or "")[:200]
        for s in sessions:
            if s.get("task_id") == task_id:
                s["last_pulse_at"] = ts
                s["heartbeat_checkpoint"] = checkpoint
                s["updated_at"] = ts
                break
        else:
            print(f"[registry] heartbeat: task not registered: {task_id}", file=sys.stderr)
            sys.exit(4)

    # PULSE-01: terminal report. `outcome` is the CALLER's claim
    # (completed/finished_empty/failed/cancelled); `evidence` is a JSON object
    # the caller computed independently (e.g. {"has_diff": true, "diff_stat_lines": N}
    # from `git diff --stat`). The reader (leadv2-lane-heartbeat.sh status),
    # not this writer, decides whether "completed" without evidence gets
    # downgraded to finished_empty -- this op just records the claim + proof
    # verbatim so that decision stays auditable and re-derivable.
    elif op == "mark_finished":
        task_id, outcome, evidence_json = args
        try:
            evidence = json.loads(evidence_json) if evidence_json not in ("", "null") else {}
        except json.JSONDecodeError as exc:
            print(f"[registry] mark_finished: invalid evidence JSON: {exc}", file=sys.stderr)
            sys.exit(2)
        if not isinstance(evidence, dict):
            print("[registry] mark_finished: evidence must be a JSON object", file=sys.stderr)
            sys.exit(2)
        now = _now_iso()
        for s in sessions:
            if s.get("task_id") == task_id:
                s["terminal_status"] = outcome
                s["terminal_evidence"] = evidence
                s["terminal_at"] = now
                s["updated_at"] = now
                break
        else:
            print(f"[registry] mark_finished: task not registered: {task_id}", file=sys.stderr)
            sys.exit(4)

    elif op == "append_provider_receipt":
        task_id, receipt_json = args
        try:
            receipt = json.loads(receipt_json)
        except json.JSONDecodeError as exc:
            print(f"[registry] invalid provider receipt JSON: {exc}", file=sys.stderr)
            sys.exit(2)
        if not isinstance(receipt, dict):
            print("[registry] provider receipt must be a JSON object", file=sys.stderr)
            sys.exit(2)
        provider = str(receipt.get("provider") or "")
        if provider not in ("claude", "codex", "glm"):
            print(f"[registry] unsupported provider receipt: {provider}", file=sys.stderr)
            sys.exit(2)
        target = next((s for s in sessions if s.get("task_id") == task_id), None)
        if target is None:
            print(f"[registry] task not registered for provider receipt: {task_id}", file=sys.stderr)
            sys.exit(4)
        receipts = target.setdefault("provider_receipts", [])
        if not isinstance(receipts, list):
            receipts = []
            target["provider_receipts"] = receipts
        receipts.append(receipt)
        # Bound registry growth while keeping enough history for diagnosis.
        if len(receipts) > 50:
            del receipts[:-50]
        target["provider"] = provider
        if receipt.get("model"):
            target["lead_model"] = receipt["model"]
        if receipt.get("effort"):
            target["lead_effort"] = receipt["effort"]
        target["updated_at"] = _now_iso()

    elif op == "set_rendered_at":
        ts_val = args[0]
        if "meta" not in data:
            data["meta"] = {}
        data["meta"]["rendered_at"] = ts_val

    # SUPERVISOR-AUDIT-01 T-E: stamp a lane's declared `writes` (comma-
    # separated paths, same convention as the tasks.yaml `writes` field --
    # see leadv2-fanout.sh's _fanout_task_lane_contract) onto its own
    # active.yaml row so leadv2-writes-overlap.sh can compare a NEW lane's
    # writes against every currently-alive lane's writes. Notify-only
    # feature (see leadv2-fanout.sh) -- this op just persists the string,
    # it makes no liveness/collision judgement itself.
    elif op == "set_writes":
        task_id, writes_csv = args
        target = next((s for s in sessions if s.get("task_id") == task_id), None)
        if target is None:
            print(f"[registry] task not registered for set_writes: {task_id}", file=sys.stderr)
            sys.exit(4)
        target["writes"] = writes_csv
        target["updated_at"] = _now_iso()

    # LANE-TRUTH-BATCH-01 Row 1: stamp the authoritative log_path AFTER
    # registration. dispatch-code.sh self-registers; the register op defaults
    # log_path to pulse.md, but the real worker stream lives at
    # docs/handoff/dispatch-<sig8>/developer.stream.jsonl. fanout's finalize
    # register (_fanout_register_session) cannot update it because its live-PID
    # guard sees dispatch-code.sh's durable PID and skips the overwrite.
    elif op == "set_log_path":
        task_id, log_path = args
        target = next((s for s in sessions if s.get("task_id") == task_id), None)
        if target is None:
            print(f"[registry] task not registered for set_log_path: {task_id}", file=sys.stderr)
            sys.exit(4)
        target["log_path"] = log_path
        target["updated_at"] = _now_iso()

    # SD-LEDGER-SWEEP-HARDEN-01: stamps the dispatch-code.sh attempt token (its own $$,
    # already used to key the dispatch-ledger's write-once-per-attempt check -- see
    # leadv2-dispatch-ledger.sh's dispatch_ledger_write_terminal doc header) onto the
    # lane's active.yaml row, mirroring set_writes above. Called AFTER the lane's final
    # registration (real pid, real log_path) -- stamping it onto the earlier pid=null
    # reservation placeholder would be silently lost, since that row gets REMOVED and
    # replaced wholesale (not merged) once the real pid is known (see
    # leadv2-fanout.sh's _fanout_register_session: `if existing: sessions.remove(existing)`
    # when the placeholder's pid is not alive).
    elif op == "set_attempt":
        task_id, attempt_id = args
        target = next((s for s in sessions if s.get("task_id") == task_id), None)
        if target is None:
            print(f"[registry] task not registered for set_attempt: {task_id}", file=sys.stderr)
            sys.exit(4)
        target["attempt"] = attempt_id
        target["updated_at"] = _now_iso()

    # LANE-REGISTRY-SELF-DEADLOCK-01: stamp the SPAWNED WORKER's pid + birth
    # onto the lane's row after a successful spawn. Mirrors set_worktree's
    # ordering-race contract (stated at the register op): an unknown task_id is
    # a SILENT no-op, rc 0 -- never an error, never a created row. A malformed
    # pid string degrades to worker_pid=None without relabelling pid_role.
    elif op == "set_worker_pid":
        task_id, pid_str, birth = args[0], args[1], args[2]
        # FORK-STORM-KILLS-HOOKS-01: 4th arg stamps WHICH KIND of process this
        # pid is. Only "worker" and "watcher" are in the vocabulary; anything
        # else degrades to "worker" (the historical, unqualified behaviour).
        # Liveness consumers (leadv2-lane-liveness.sh) ignore a "watcher" pid
        # as liveness evidence -- a watcher is not a worker.
        _role = args[3] if len(args) > 3 else "worker"
        if _role not in ("worker", "watcher"):
            _role = "worker"
        target = next((s for s in sessions if s.get("task_id") == task_id), None)
        if target is None:
            sys.exit(0)
        try:
            wpid = int(pid_str) if pid_str not in ("", "null", "None") else None
        except (TypeError, ValueError):
            wpid = None
        target["worker_pid"] = wpid
        target["worker_pid_birth"] = birth if birth not in ("", "null", "None") else None
        target["worker_pid_role"] = _role
        if wpid is not None and wpid > 0:
            # The post-spawn process is now the lane's authoritative liveness
            # owner.  Keep the legacy `pid` fields aligned with worker_pid:
            # older readers still consult `pid`, while newer liveness code
            # prefers worker_pid.  Leaving the initial dispatch/lead ancestor
            # here makes either reader report the wrong lane lifetime.
            target["pid"] = wpid
            target["pid_birth"] = target["worker_pid_birth"]
            target["pid_role"] = _role
        target["updated_at"] = _now_iso()

    else:
        print(f"[registry] unknown op: {op}", file=sys.stderr)
        sys.exit(1)

    # Atomic write: temp + rename
    dir_ = os.path.dirname(yaml_path)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=dir_, suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as tf:
            yaml.dump(data, tf, default_flow_style=False, sort_keys=False)
        try:
            os.replace(tmp_path, yaml_path)
        except (OSError, PermissionError):
            # Sandboxed callers (e.g. codex CLI's stricter --sandbox
            # enforcement) can reject a rename that crosses a symlink
            # boundary even though a direct write to the target succeeds.
            # Still under the flock -- fall back to overwriting the target
            # file in place instead of rename+replace.
            with open(yaml_path, "w", encoding="utf-8") as tf2:
                yaml.dump(data, tf2, default_flow_style=False, sort_keys=False)
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

finally:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
PYEOF
}

# ── Public functions ───────────────────────────────────────────────────────

# _lv2_durable_pid — walk $PPID chain to find the durable 'claude' process PID.
# Returns the claude process PID on stdout, or PPID as fallback.
# Rationale: gate1-prompt.sh runs as a short-lived bash subprocess; stale-pid-sweep
# drops any session whose pid is dead at next SessionStart. Registering with the
# durable claude process PID keeps the session alive until the real session ends.
_lv2_durable_pid() {
  python3 - "$PPID" <<'PYEOF' || printf -- '%s' "$PPID"
import sys, subprocess
from typing import Optional

def ppid_of(pid: int) -> Optional[int]:
    try:
        r = subprocess.run(
            ['ps', '-o', 'ppid=', '-p', str(pid)],
            capture_output=True, text=True, timeout=2
        )
        s = r.stdout.strip()
        return int(s) if s else None
    except Exception:
        return None

def comm_of(pid: int) -> str:
    try:
        r = subprocess.run(
            ['ps', '-o', 'comm=', '-p', str(pid)],
            capture_output=True, text=True, timeout=2
        )
        return r.stdout.strip().split('/')[-1].lower()
    except Exception:
        return ''

start = int(sys.argv[1])
pid = start
visited: set = set()
while pid and pid > 1 and pid not in visited:
    visited.add(pid)
    if 'claude' in comm_of(pid):
        print(pid, end='')
        sys.exit(0)
    nxt = ppid_of(pid)
    if nxt is None or nxt == pid or nxt == 1:
        break
    pid = nxt
# fallback: start is PPID of the bash script (caller's shell), reasonably durable
print(start, end='', file=sys.stdout)
print(f'[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid={start}', file=sys.stderr)
PYEOF
}

# _lv2_pid_birth <pid> — canonical `ps -o lstart=` reader/writer trim.
# LANE-LIVENESS-LIES-01 Change 1a: `tr -s ' '` alone collapses interior runs but
# Darwin's `ps -o lstart=` right-pads the field, leaving a trailing space the
# reader's `.strip()` removes -- so writer and reader never compared equal and
# every healthy lane failed birth corroboration. Do not "simplify" back to
# `tr -s ' '`. LANE-REGISTRY-SELF-DEADLOCK-01: extracted here so the register
# writer and the post-spawn set_worker_pid stamp can never drift apart.
_lv2_pid_birth() {
  ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//' || printf -- 'unknown'
}

# leadv2_active_register <task_id> <class> <worktree> <branch> <daemon_mode>
#                         [<group_key>] [<risk_tags>] [<writes>]
# Writes a new session row to active.yaml.
# Returns (stdout): session_id in format s-YYYYMMDDTHHMMSSZ-PID
# Returns (exit code): 0 ok; 5/6 on a LANE-WRITESET-REGISTRY-01 admission
# refusal when <writes> is non-empty (see exit-code header block above) --
# additive 8th positional arg, defaults to "-" so every existing caller
# (including leadv2-fanout.sh, untouched by this change) keeps working.
leadv2_active_register() {
  local task_id="${1:?task_id required}"
  local cls="${2:-Standard}"
  local worktree="${3:-$(pwd)}"
  local branch="${4:-}"
  local daemon_mode="${5:-false}"
  local group_key="${6:-}"
  local risk_tags="${7:-}"
  local writes="${8:--}"

  if [[ -z "$branch" ]]; then
    branch="$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || printf -- 'unknown')"
  fi

  # Use the durable claude process PID so stale-pid-sweep doesn't drop the row
  # at the next SessionStart when the gate1 bash subprocess has already exited.
  local durable_pid
  durable_pid="$(_lv2_durable_pid)"

  local session_id ts pid_birth pulse_log parent_sid
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  # Tiebreaker: append $$ (gate1 subprocess pid, unique per invocation) after durable_pid.
  # durable_pid is the liveness key; $$ ensures uniqueness when two tasks register same second.
  session_id="s-$(date -u +%Y%m%dT%H%M%SZ)-${durable_pid}-$$"
  pid_birth="$(_lv2_pid_birth "${durable_pid}")"
  pulse_log="docs/leadv2/tasks/${task_id}/pulse.md"
  parent_sid="${LEADV2_PARENT_SESSION_ID:-null}"

  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"

  local _register_rc=0
  _leadv2_yaml_py_lock \
    "$lockfile" "$yaml_file" register \
    "$session_id" "$task_id" "$worktree" "$branch" "$ts" \
    "intake" "$cls" "${durable_pid}" "$pid_birth" "$parent_sid" \
    "$daemon_mode" "$ts" "$pulse_log" "$group_key" "$risk_tags" "$writes" || _register_rc=$?

  # LANE-WRITESET-REGISTRY-01 step 3: propagate the python op's exit code
  # instead of swallowing it -- a writeset admission refusal (rc 5/6) must
  # reach the caller so cmd_resolve can refuse the dispatch before spawn.
  if [[ "${_register_rc}" -ne 0 ]]; then
    return "${_register_rc}"
  fi

  # Auto-refresh LEAD_V2_STATE.md on every register — non-fatal to register itself
  _render_log="/tmp/lv2-render-$(date +%s).log"
  leadv2_active_render_index 2>"$_render_log" || {
    printf -- '[registry] WARN: render_index failed after register:\n' >&2
    cat "$_render_log" >&2
  }
}

# leadv2_active_check_writes_conflict <task_id> <writes_csv>
# LANE-WRITESET-REGISTRY-01 D5/D6: read-only re-check for the commit-time
# drift check -- never persists, never appends/refreshes a row. Returns
# 0/5/6 exactly like leadv2_active_register's admission check.
leadv2_active_check_writes_conflict() {
  local task_id="${1:?task_id required}" writes_csv="${2:-}"
  local yaml_file lockfile rc=0
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 0
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" check_writes "$task_id" "$writes_csv" || rc=$?
  return "$rc"
}

# leadv2_active_set_worktree <task_id> <worktree>
# Idempotently records where this lane actually runs. Unknown task IDs are a
# no-op in the python op so launcher/register ordering races never kill a lane.
leadv2_active_set_worktree() {
  local task_id="${1:?task_id required}" wt="${2:?worktree required}"
  [[ -d "$wt" ]] || return 0
  _leadv2_yaml_py_lock "$(_leadv2_yaml_lockfile)" "$(_leadv2_yaml_file)" set_worktree "$task_id" "$wt"
}

# leadv2_active_set_log_path <task_id> <log_path>
# Stamps the authoritative log_path (stream file) for liveness resolution.
# LANE-TRUTH-BATCH-01 Row 1: dispatch-code.sh self-registers with the default
# pulse.md path; this corrects it to docs/handoff/dispatch-<sig8>/developer.stream.jsonl
# so liveness resolves the real stream instead of falling through to dead:no_handoff_dir.
leadv2_active_set_log_path() {
  local task_id="${1:?task_id required}" log_path="${2:?log_path required}"
  _leadv2_yaml_py_lock "$(_leadv2_yaml_lockfile)" "$(_leadv2_yaml_file)" set_log_path "$task_id" "$log_path"
}

# leadv2_active_unregister <task_id>
leadv2_active_unregister() {
  local task_id="${1:?task_id required}"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 0
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" unregister "$task_id"

  # Auto-refresh LEAD_V2_STATE.md on every unregister — non-fatal to unregister itself
  _render_log="/tmp/lv2-render-$(date +%s).log"
  leadv2_active_render_index 2>"$_render_log" || {
    printf -- '[registry] WARN: render_index failed after unregister:\n' >&2
    cat "$_render_log" >&2
  }
}

# leadv2_active_update_phase [<task_id>] <phase> [<resolved_model>]
# Legacy 1-arg form (several phase skills call this with phase only, e.g.
# `leadv2_active_update_phase "$PHASE"`) resolves task_id from
# $LEADV2_TASK_ID. V2 2-arg form is the explicit, preferred call. Optional
# 3rd arg (V2 form only) also stamps lead_model -- see the update_phase op's
# model-stamp comment above; omitted/empty is a no-op, so every pre-existing
# caller is unaffected. Both forms converge on the same python op — normalize
# here, not in the python core.
leadv2_active_update_phase() {
  local task_id phase model
  if [[ $# -ge 2 ]]; then
    task_id="${1:?task_id required}"
    phase="${2:?phase required}"
    model="${3:-}"
  else
    task_id="${LEADV2_TASK_ID:?leadv2_active_update_phase: 1-arg legacy form requires LEADV2_TASK_ID to be set}"
    phase="${1:?phase required}"
    model=""
  fi
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 0
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" update_phase "$task_id" "$phase" "$model"
}

# leadv2_active_update_pulse <task_id>
leadv2_active_update_pulse() {
  local task_id="${1:?task_id required}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 0
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" update_pulse "$task_id" "$ts"
}

# leadv2_active_heartbeat <task_id> <checkpoint>
# Durable per-task heartbeat (PULSE-01). Call at low cadence (not per tool
# call) from any arm's wrapper/hook. Returns non-zero if task_id is not
# registered.
leadv2_active_heartbeat() {
  local task_id="${1:?task_id required}"
  local checkpoint="${2:-}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 4
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" heartbeat "$task_id" "$ts" "$checkpoint"
}

# leadv2_active_mark_finished <task_id> <outcome> [<evidence_json>]
# outcome: completed | finished_empty | failed | cancelled
# evidence_json: JSON object the caller computed (default '{}' = no proof of
# output -- the reader treats outcome=completed with empty evidence as
# finished_empty, never trusting a bare self-report).
leadv2_active_mark_finished() {
  local task_id="${1:?task_id required}"
  local outcome="${2:?outcome required}"
  local evidence_json="${3:-}"
  [[ -n "$evidence_json" ]] || evidence_json='{}'
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 4
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" mark_finished "$task_id" "$outcome" "$evidence_json"
}

# leadv2_active_append_provider_receipt <task_id> <receipt_json>
# Appends an auditable provider/run receipt under the same active.yaml lock.
leadv2_active_append_provider_receipt() {
  local task_id="${1:?task_id required}"
  local receipt_json="${2:?receipt_json required}"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 4
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" append_provider_receipt "$task_id" "$receipt_json"
}

# leadv2_active_set_writes <task_id> <writes_csv>
# SUPERVISOR-AUDIT-01 T-E: stamps a comma-separated writes list onto the
# task's existing active.yaml row (no-op create -- the row must already
# exist, e.g. from leadv2_active_register / fanout's own reservation).
leadv2_active_set_writes() {
  local task_id="${1:?task_id required}"
  local writes_csv="${2:?writes_csv required}"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 4
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" set_writes "$task_id" "$writes_csv"
}

# leadv2_active_set_attempt <task_id> <attempt_id>
# SD-LEDGER-SWEEP-HARDEN-01: stamps the dispatch-ledger attempt token onto the task's
# existing active.yaml row (no-op create -- the row must already exist). Call this
# AFTER the lane's final registration with a real pid, not on the pre-spawn placeholder
# -- see leadv2-active-registry.sh's own set_attempt op doc comment for why.
leadv2_active_set_attempt() {
  local task_id="${1:?task_id required}"
  local attempt_id="${2:?attempt_id required}"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 4
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" set_attempt "$task_id" "$attempt_id"
}

# leadv2_active_set_worker_pid <task_id> <pid> <pid_birth> [role]
# LANE-REGISTRY-SELF-DEADLOCK-01: post-spawn stamp of the WORKER process
# identity onto the lane's active.yaml row. Unknown task_id is a silent no-op
# in the python op (register/spawn ordering races must never kill a lane), so
# callers run this with `|| true` -- a stamp failure must never fail a dispatch.
# FORK-STORM-KILLS-HOOKS-01: optional 4th arg `role` -- "worker" (default) or
# "watcher". The dispatcher-owned lane-pulse watcher is NOT a worker: a row
# pinned to it must never read as process-liveness evidence (the closed loop
# where a stale watcher made every later dispatch refuse with lane_is_live).
leadv2_active_set_worker_pid() {
  local task_id="${1:?task_id required}" pid="${2:?pid required}" pid_birth="${3:-}"
  local role="${4:-worker}"
  local yaml_file lockfile
  yaml_file="$(_leadv2_yaml_file)"
  lockfile="$(_leadv2_yaml_lockfile)"
  [[ -f "$yaml_file" ]] || return 0
  _leadv2_yaml_py_lock "$lockfile" "$yaml_file" set_worker_pid "$task_id" "$pid" "$pid_birth" "$role"
}

# leadv2_active_render_index
# Regenerates docs/LEAD_V2_STATE.md as markdown index from active.yaml.
leadv2_active_render_index() {
  local yaml_file state_md ts
  yaml_file="$(_leadv2_yaml_file)"
  state_md="$(_leadv2_state_md)"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  mkdir -p "$(dirname "$state_md")"

  python3 - "$yaml_file" "$state_md" "$ts" <<'PYEOF'
import sys, os
try:
    import yaml
except ImportError:
    print("[registry] PyYAML not found", file=sys.stderr)
    sys.exit(1)

yaml_file, state_md, ts = sys.argv[1], sys.argv[2], sys.argv[3]

if not os.path.exists(yaml_file):
    sessions = []
    hard_limit = 2
else:
    with open(yaml_file, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    sessions = data.get("sessions") or []
    hard_limit = (data.get("meta") or {}).get("hard_limit", 2)

# Preserve "## Recent history" block from prior render so it survives regeneration.
# Block ends at next H2 heading or EOF. Lead/founder edits this section by hand.
# Uses re.MULTILINE so the match is anchored to line-start, not inside HTML comments.
import re
history_block = ""
if os.path.exists(state_md):
    with open(state_md, encoding="utf-8") as fh:
        prior = fh.read()
    m = re.search(r'^## Recent history', prior, re.MULTILINE)
    if m:
        tail = prior[m.start():]
        next_h2 = tail.find("\n## ", 1)
        history_block = tail if next_h2 == -1 else tail[:next_h2]
        history_block = history_block.rstrip() + "\n"

lines = [
    "<!-- DO NOT EDIT TABLE — regenerated from docs/leadv2/active.yaml by leadv2_active_render_index -->",
    "<!-- Per-task state: docs/leadv2/tasks/<task_id>/STATE.md -->",
    "<!-- '## Recent history' below is preserved across renders; edit by hand. -->",
    "",
    "# /leadv2 Active Sessions",
    "",
    f"Last updated: {ts}",
    "",
    "| task_id | phase | class | started_at | daemon |",
    "|---|---|---|---|---|",
]

for s in sessions:
    tid     = s.get("task_id", "?")
    phase   = s.get("phase", "?")
    cls     = s.get("class", "?")
    started = (s.get("started_at") or "")[:16]
    daemon  = "yes" if s.get("daemon_mode") else "no"
    lines.append(f"| {tid} | {phase} | {cls} | {started} | {daemon} |")

lines.append("")
lines.append(f"Sessions: {len(sessions)} / {hard_limit} max")
lines.append("")

out = "\n".join(lines) + "\n"
if history_block:
    out += "\n" + history_block

with open(state_md, "w", encoding="utf-8") as fh:
    fh.write(out)
print(f"[registry] rendered {state_md} ({len(sessions)} sessions, history_preserved={bool(history_block)})")
PYEOF

  # Write rendered_at back to active.yaml under the same lock discipline (non-fatal)
  local lockfile
  lockfile="$(_leadv2_yaml_lockfile)"
  if [[ -f "$yaml_file" ]]; then
    _leadv2_yaml_py_lock "$lockfile" "$yaml_file" set_rendered_at "$ts" \
      || printf -- '[registry] WARN: rendered_at write to active.yaml failed (non-fatal)\n' >&2
  fi
}

# leadv2_active_list [--peers-json <file>]
# Prints active.yaml sessions as a human-readable table to stdout.
# LANE-WRITESET-REGISTRY-01 D8: the `peer` column is populated from an
# OPTIONAL --peers-json file the LEAD writes from its own ListAgents call --
# this shell function cannot call ListAgents itself (harness tool, not a
# command). Absent/unparseable peers-json is never silent: every row renders
# peer="?" and the footer states the registry-only view explicitly.
leadv2_active_list() {
  local yaml_file peers_json=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --peers-json) peers_json="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  yaml_file="$(_leadv2_yaml_file)"

  if [[ ! -f "$yaml_file" ]]; then
    echo "[registry] no active.yaml found at $yaml_file"
    return 0
  fi

  python3 - "$yaml_file" "$peers_json" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    print("[registry] PyYAML not found", file=sys.stderr)
    sys.exit(1)

yaml_file, peers_path = sys.argv[1], sys.argv[2]

with open(yaml_file, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
sessions = data.get("sessions") or []
meta = data.get("meta") or {}

peers_by_key = {}
peers_available = False
if peers_path:
    try:
        import json
        with open(peers_path, encoding="utf-8") as pfh:
            peers_raw = json.load(pfh)
        for row in (peers_raw or []):
            if not isinstance(row, dict):
                continue
            key = row.get("session_id") or row.get("task_id")
            if key:
                peers_by_key[str(key)] = row.get("peer") or row.get("name") or "?"
        peers_available = True
    except Exception:
        peers_available = False

print(f"Active sessions ({len(sessions)} / {meta.get('hard_limit', 2)} max):")
print(f"{'session_id':<30} {'task_id':<20} {'phase':<12} {'class':<10} {'pid':<8} {'daemon':<7} {'writes':<20} {'peer':<12} {'stale'}")
print("-" * 130)
for s in sessions:
    sid    = (s.get("session_id") or "?")[:28]
    tid_full = s.get("task_id") or "?"
    tid    = tid_full[:18]
    phase  = (s.get("phase") or "?")[:10]
    cls    = (s.get("class") or "?")[:8]
    pid    = str(s.get("pid") or "null")[:6]
    daemon = "yes" if s.get("daemon_mode") else "no"
    stale  = "STALE" if s.get("stale") else "-"
    # LANE-WRITESET-REGISTRY-01: "?" (never silently absent) when the row
    # carries neither `writes` nor the `write_set` alias -- the D7 unknown
    # state must be visible in the table, not blank.
    writes_raw = s.get("writes")
    if writes_raw is None:
        writes_raw = s.get("write_set")
    if writes_raw is None:
        writes_col = "?"
    elif writes_raw in ("", "-"):
        writes_col = "-"
    else:
        writes_col = str(writes_raw)
    # L3: mark truncation visibly -- a silently shortened CSV reads as a
    # different, still-plausible write set otherwise.
    writes_col = (writes_col[:17] + "…") if len(writes_col) > 18 else writes_col
    if peers_available:
        # M4: lookup keyed on the FULL task_id, not the 18-char display
        # truncation -- reg_id is routinely "dispatch-<sig8>" plus longer
        # founder ids, so a truncated key can never match a peers-json entry.
        peer = peers_by_key.get(str(s.get("session_id")), peers_by_key.get(str(tid_full), "?"))
    else:
        peer = "?"
    peer = str(peer)[:10]
    print(f"{sid:<30} {tid:<20} {phase:<12} {cls:<10} {pid:<8} {daemon:<7} {writes_col:<20} {peer:<12} {stale}")

if not peers_available:
    print("peers: unavailable — registry-only view")
PYEOF
}

# leadv2_active_check_limits <class>
# Exit codes: 0=OK, 1=hard_limit_reached, 2=heavy_conflict, 3=budget_refused
leadv2_active_check_limits() {
  local cls="${1:-Standard}"
  local yaml_file overrides_file
  yaml_file="$(_leadv2_yaml_file)"
  overrides_file="${LEADV2_PROJECT_ROOT}/.claude/leadv2-overrides/active-limits.yaml"

  python3 - "$yaml_file" "$cls" "$overrides_file" <<'PYEOF'
import sys, os
try:
    import yaml
except ImportError:
    sys.exit(0)  # fail open if yaml missing

yaml_file, cls, overrides_file = sys.argv[1], sys.argv[2], sys.argv[3]

if not os.path.exists(yaml_file):
    sys.exit(0)

with open(yaml_file, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

meta = data.get("meta") or {}
sessions = [s for s in (data.get("sessions") or []) if not s.get("stale")]

# Repo-local override (per leadv2-overrides/active-limits.yaml) wins over active.yaml meta
overrides = {}
if os.path.exists(overrides_file):
    try:
        with open(overrides_file, encoding="utf-8") as fh:
            overrides = yaml.safe_load(fh) or {}
    except Exception as e:
        print(f"[registry] WARN: failed to read overrides {overrides_file}: {e}", file=sys.stderr)

def _resolve(key, default):
    if key in overrides:
        return overrides[key]
    if key in meta:
        return meta[key]
    return default

def _key_present(key):
    return key in overrides or key in meta

hard_limit   = _resolve("hard_limit", 3)
light_max    = _resolve("light_max", 3)
standard_max = _resolve("standard_max", 2)

# HEAVY-MAX-2-WITH-COLLISION-GUARD-01 (F4): heavy_max is the SOLE control for
# concurrent Heavy/strategic lanes, mirroring leadv2-fanout.sh's selection
# pass (the OTHER reader of these caps). Legacy heavy_strategic_solo is
# honored as the fallback default ONLY when heavy_max is absent entirely
# (very old active.yaml, back-compat) -- otherwise it is an explicit
# kill-switch a founder can flip True to force serialize.
heavy_max = _resolve("heavy_max", 3)
if _key_present("heavy_max"):
    heavy_strategic_solo = _resolve("heavy_strategic_solo", False)
else:
    heavy_strategic_solo = _resolve("heavy_strategic_solo", True)

cls_l = cls.lower()

# Check hard limit (total active sessions, all classes) -- hard ceiling, never bypassed here.
if len(sessions) >= hard_limit:
    print(f"[registry] hard limit reached: {len(sessions)}/{hard_limit} active sessions", file=sys.stderr)
    sys.exit(1)

# Check heavy/strategic: solo kill-switch, else heavy_max ceiling. This
# function has no collision-guard (no group_key/risk_tags input) -- it is a
# coarser, conservative cap used by callers that only know `cls`.
if cls_l in ("heavy", "strategic"):
    heavy_count = sum(1 for s in sessions if s.get("class", "").lower() in ("heavy", "strategic"))
    if heavy_strategic_solo:
        if heavy_count > 0:
            print(f"[registry] heavy/strategic conflict: solo rule -- a Heavy/strategic session already active", file=sys.stderr)
            sys.exit(2)
    elif heavy_count >= heavy_max:
        print(f"[registry] heavy_max reached: {heavy_count}/{heavy_max}", file=sys.stderr)
        sys.exit(2)

# Per-class caps
def _count(label):
    return sum(1 for s in sessions if s.get("class", "").lower() == label)

if cls_l == "light" and _count("light") >= light_max:
    print(f"[registry] light cap reached: {_count('light')}/{light_max}", file=sys.stderr)
    sys.exit(1)

# Standard cap counts Standard + Standard-light (treated equally)
if cls_l in ("standard", "standard-light"):
    std_count = sum(1 for s in sessions if s.get("class", "").lower() in ("standard", "standard-light"))
    if std_count >= standard_max:
        print(f"[registry] standard cap reached: {std_count}/{standard_max}", file=sys.stderr)
        sys.exit(1)

sys.exit(0)
PYEOF
}
