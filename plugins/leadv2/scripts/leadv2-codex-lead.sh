#!/usr/bin/env bash
# leadv2-codex-lead.sh — Phase-0 intake for `/leadv2 codex [task-id|next]`.
#
# The wrapper resolves and claims one queued task, refuses duplicate live work,
# creates the lane, then detaches the existing full-cycle Codex session runner.
# The runner has no positional CLI: its contract is LEADV2_TASK_ID plus
# LEADV2_PROJECT_ROOT (CLAUDE_PROJECT_DIR is exported consistently as well).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Private detach trampoline. Keeping this in the wrapper lets the parent return
# a relay handle while still removing the job-registry entry when the runner
# exits. The session runner itself receives exactly zero positional arguments.
if [[ "${LEADV2_CODEX_LEAD_INTERNAL:-0}" == "1" && "${1:-}" == "--run-detached" ]]; then
  [[ $# -eq 6 ]] || exit 64
  _registry_entry="$2"
  _runner_bin="$3"
  _task_id="$4"
  _shared_root="$5"
  _lane_dir="$6"
  # shellcheck disable=SC2329  # invoked indirectly by the EXIT trap
  _internal_cleanup() { rm -f -- "$_registry_entry" 2>/dev/null || true; }
  trap _internal_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  cd -- "$_lane_dir"
  set +e
  LEADV2_TASK_ID="$_task_id" \
  LEADV2_PROJECT_ROOT="$_shared_root" \
  CLAUDE_PROJECT_DIR="$_shared_root" \
  PROJECT_ROOT="$_shared_root" \
    "$_runner_bin"
  _runner_rc=$?
  set -e
  exit "$_runner_rc"
fi

printf -- 'ADVISORY: this session needs no Opus brain; use /model sonnet — the thinking runs on Codex.\n'

refuse() {
  printf -- 'leadv2 codex refused: %s\n' "$*" >&2
  exit 1
}

if [[ $# -gt 1 ]]; then
  refuse 'expected [task-id|next]'
fi

REQUEST="${1:-next}"
if [[ -z "$REQUEST" ]]; then
  REQUEST="next"
fi

PROJECT_ROOT="${LEADV2_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-${PROJECT_ROOT:-}}}"
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT" ]] || refuse 'project root is unavailable'
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
readonly PROJECT_ROOT
export PROJECT_ROOT

TASKS_FILE="$PROJECT_ROOT/docs/tasks.yaml"
TASKS_LIB="${LEADV2_CODEX_LEAD_TASKS_LIB:-$SCRIPT_DIR/leadv2-tasks-lib.sh}"
RUNNER_BIN="${LEADV2_CODEX_LEAD_RUNNER_BIN:-$SCRIPT_DIR/leadv2-codex-session-runner.sh}"
STATE_PATH_BIN="${LEADV2_CODEX_LEAD_STATE_PATH_BIN:-$SCRIPT_DIR/leadv2-state-path.sh}"
LANE_WORKTREE_BIN="${LEADV2_CODEX_LEAD_LANE_WORKTREE_BIN:-$SCRIPT_DIR/leadv2-lane-worktree.sh}"

[[ -r "$TASKS_FILE" ]] || refuse "task queue is unavailable: $TASKS_FILE"
[[ -r "$TASKS_LIB" ]] || refuse "tasks library is unavailable: $TASKS_LIB"
[[ -x "$RUNNER_BIN" ]] || refuse "session runner is unavailable: $RUNNER_BIN"
[[ -x "$LANE_WORKTREE_BIN" ]] || refuse "lane worktree helper is unavailable: $LANE_WORKTREE_BIN"

# shellcheck disable=SC1090,SC1091  # TASKS_LIB is an intentional test/runtime seam
source "$TASKS_LIB"

TASK_ID=""
TASK_ROW=""
if [[ "$REQUEST" == "next" ]]; then
  _top_rows="$(leadv2_tasks_top_n 100000 2>/dev/null || true)"
  [[ -n "$_top_rows" ]] || refuse 'no queued, unclaimed, unblocked task is available'
  _skipped_candidates=()
  while IFS=$'\t' read -r _lane _priority _candidate_id _title; do
    [[ -n "$_candidate_id" ]] || continue
    _candidate_row="$(leadv2_tasks_by_id "$_candidate_id" 2>/dev/null || true)"
    if [[ -z "$_candidate_row" ]]; then
      _skipped_candidates+=("$_candidate_id:missing-row")
      continue
    fi
    _candidate_filter="$(python3 - "$_candidate_row" <<'PYEOF'
import re
import sys
import yaml

try:
    rows = yaml.safe_load(sys.argv[1]) or []
    row = rows[0] if rows else {}
    priority = str(row.get("priority", "medium")).strip().lower()
    intent = str(row.get("intent") or "")
except Exception:
    raise SystemExit(2)

known = {"critical", "high", "medium", "low"}
if priority not in known:
    if not re.fullmatch(r"[0-9]+", priority):
        print(f"unknown-priority={priority or 'empty'}")
        raise SystemExit(0)
    if int(priority) >= 900:
        print(f"reserved-priority={priority}")
        raise SystemExit(0)
if re.search(r"^DUPLICATE|DO NOT DISPATCH", intent, re.IGNORECASE):
    print("duplicate-marker")
    raise SystemExit(0)
print("eligible")
PYEOF
)" || refuse "task row is invalid: $_candidate_id"
    if [[ "$_candidate_filter" == "eligible" ]]; then
      TASK_ID="$_candidate_id"
      TASK_ROW="$_candidate_row"
      break
    fi
    _skipped_candidates+=("$_candidate_id:$_candidate_filter")
  done <<< "$_top_rows"
  if [[ -z "$TASK_ID" ]]; then
    refuse "no eligible task remains after poisoned-row filtering (skipped: ${_skipped_candidates[*]:-none})"
  fi
else
  TASK_ID="$REQUEST"
fi

[[ "$TASK_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || refuse 'task id contains unsafe characters'
if [[ -z "$TASK_ROW" ]]; then
  TASK_ROW="$(leadv2_tasks_by_id "$TASK_ID" 2>/dev/null || true)"
fi
[[ -n "$TASK_ROW" ]] || refuse "task not found: $TASK_ID"

# Parse the queue row once for claim guards. Support both the tasks-lib claim
# object and generated task projections that expose claimed_by/lease directly.
_task_meta="$(python3 - "$TASK_ROW" <<'PYEOF'
import sys, yaml
try:
    rows = yaml.safe_load(sys.argv[1]) or []
    row = rows[0] if rows else {}
    claim = row.get("claim") or {}
    by = claim.get("by")
    if by in (None, ""):
        by = row.get("claimed_by")
    lease = claim.get("lease_expires")
    if lease in (None, ""):
        lease = row.get("claim_lease_until")
    clean = lambda value: str(value or "").replace("|", "/").replace("\n", " ")
    print("|".join((clean(row.get("status")), clean(by), clean(lease))))
except Exception:
    raise SystemExit(2)
PYEOF
)" || refuse "task row is invalid: $TASK_ID"
IFS='|' read -r TASK_STATUS TASK_CLAIM_BY TASK_CLAIM_LEASE <<< "$_task_meta"

case "$TASK_STATUS" in
  pending|queued) ;;
  *) refuse "task $TASK_ID is not claimable (status=${TASK_STATUS:-unknown})" ;;
esac
[[ -z "$TASK_CLAIM_BY" ]] || refuse "task $TASK_ID already has a live claim by $TASK_CLAIM_BY (lease=${TASK_CLAIM_LEASE:-unknown})"

# Match dispatch-code.sh's task signature: the fanout mission is title + note
# + origin, normalized by whitespace before SHA-256. Intent is accepted as a
# projection fallback; task id is the final stable fallback for sparse rows.
TASK_MISSION="$(python3 - "$TASK_ROW" "$TASK_ID" <<'PYEOF'
import sys, yaml
rows = yaml.safe_load(sys.argv[1]) or []
row = rows[0] if rows else {}
title = row.get("title") or row.get("intent") or ""
note = row.get("note") or ""
origin = row.get("origin") or ""
parts = [str(v) for v in (title, note) if v]
if origin:
    parts.append(f"(origin: {origin})")
print(" — ".join(parts) if parts else sys.argv[2], end="")
PYEOF
)" || refuse "could not derive task signature: $TASK_ID"
TASK_SIG="$(printf '%s' "$TASK_MISSION" | tr -d '\r' | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//' | shasum -a 256 | awk '{print $1}')"
[[ "$TASK_SIG" =~ ^[0-9a-f]{64}$ ]] || refuse "could not derive task signature: $TASK_ID"
SIG8="${TASK_SIG:0:8}"
readonly TASK_ID TASK_SIG SIG8

TASK_BRANCH="worktree-$TASK_ID"
RUNNER_LOG="$PROJECT_ROOT/docs/handoff/$TASK_ID/codex-session-runner.log"

_repo_slug="$(basename "$PROJECT_ROOT" | tr -cd 'A-Za-z0-9._-')"
_dispatch_cache="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}"
DISPATCH_LEDGER_FILE="${LEADV2_CODEX_LEAD_DISPATCH_LEDGER_FILE:-${DISPATCH_LEDGER_DIR:-${_dispatch_cache}/dispatch-ledger}/${_repo_slug}.jsonl}"
JOB_REGISTRY_ROOT="${LEADV2_JOB_REGISTRY_ROOT:-/tmp/leadv2-job-registry}"
ACTIVE_FILE="${LEADV2_CODEX_LEAD_ACTIVE_FILE:-}"
TERMINAL_LEDGER_FILE="${LEADV2_CODEX_LEAD_TERMINAL_LEDGER_FILE:-${LEADV2_DISPATCH_TERMINAL_LEDGER_FILE:-}}"
if [[ -z "$ACTIVE_FILE" && -x "$STATE_PATH_BIN" ]]; then
  ACTIVE_FILE="$(env PROJECT_ROOT="$PROJECT_ROOT" LEADV2_PROJECT_ROOT="$PROJECT_ROOT" \
    "$STATE_PATH_BIN" --no-link active.yaml 2>/dev/null || true)"
fi
if [[ -z "$TERMINAL_LEDGER_FILE" && -x "$STATE_PATH_BIN" ]]; then
  TERMINAL_LEDGER_FILE="$(env PROJECT_ROOT="$PROJECT_ROOT" LEADV2_PROJECT_ROOT="$PROJECT_ROOT" \
    "$STATE_PATH_BIN" --no-link dispatch-ledger.jsonl 2>/dev/null || true)"
fi
if [[ -z "$TERMINAL_LEDGER_FILE" ]]; then
  TERMINAL_LEDGER_FILE="${_dispatch_cache}/dispatch-terminal-ledger/${_repo_slug}.jsonl"
fi

# One read-only duplicate predicate covers the open dispatch reservation, the
# write-once terminal ledger, an exact provider/job handle, and the shared
# active-session claim. It mirrors dispatch-code's pending/confirmed TTLs so
# abandoned historical rows do not become permanent lockouts; malformed
# live-state evidence fails closed.
_guard_reason=""
set +e
_guard_reason="$(python3 - "$DISPATCH_LEDGER_FILE" "$TERMINAL_LEDGER_FILE" "$JOB_REGISTRY_ROOT" "$ACTIVE_FILE" \
  "$TASK_SIG" "$SIG8" "$TASK_ID" \
  "${LEADV2_DISPATCH_PENDING_TTL_S:-30}" "${LEADV2_DISPATCH_CONFIRMED_TTL_S:-7200}" <<'PYEOF'
import glob, json, os, sys, time

ledger, terminal_ledger, jobs, active, sig, sig8, task_id, pending_ttl, confirmed_ttl = sys.argv[1:]
pending_ttl, confirmed_ttl = int(pending_ttl), int(confirmed_ttl)
now = int(time.time())
handles = set()

def same_task(row):
    return (
        str(row.get("task_sig") or "") in {sig, sig8}
        or str(row.get("founder_task_id") or "") == task_id
        or str(row.get("task_id") or "") == task_id
    )

if ledger and os.path.exists(ledger):
    try:
        with open(ledger, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if not raw.strip():
                    continue
                try:
                    row = json.loads(raw)
                except Exception:
                    continue
                if not isinstance(row, dict) or not same_task(row):
                    continue
                handle = str(row.get("handle") or "")
                if handle:
                    handles.add(os.path.basename(handle))
                state = str(row.get("state") or "")
                if state not in {"pending", "confirmed"}:
                    continue
                try:
                    created = int(row.get("created_epoch") or 0)
                except Exception:
                    created = 0
                ttl = pending_ttl if state == "pending" else confirmed_ttl
                if created <= 0 or now - created < ttl:
                    print(f"dispatch ledger has an open {state} row for signature {sig8}")
                    raise SystemExit(2)
    except OSError:
        print("dispatch ledger is unreadable")
        raise SystemExit(3)

if terminal_ledger and os.path.exists(terminal_ledger):
    last_terminal = ""
    try:
        with open(terminal_ledger, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if not raw.strip():
                    continue
                try:
                    row = json.loads(raw)
                except Exception:
                    continue
                if not isinstance(row, dict):
                    continue
                if str(row.get("task_sig") or "") not in {sig, sig8}:
                    continue
                last_terminal = str(row.get("terminal") or "").lower()
    except OSError:
        print("terminal ledger is unreadable")
        raise SystemExit(3)
    if last_terminal == "landed":
        print(f"terminal ledger records landed for signature {sig8} (already completed)")
        raise SystemExit(2)
    if last_terminal == "dead":
        print(f"terminal ledger records dead for signature {sig8} (founder/lead re-plan required)")
        raise SystemExit(2)
    if last_terminal in {"parked", "refused", "no_work"}:
        print(
            f"leadv2 codex warning: prior terminal {last_terminal} for signature {sig8}; retry remains allowed",
            file=sys.stderr,
        )

if jobs and os.path.isdir(jobs):
    try:
        entries = glob.glob(os.path.join(jobs, "*", "*"))
        for entry in entries:
            if not os.path.isfile(entry):
                continue
            name = os.path.basename(entry)
            try:
                with open(entry, encoding="utf-8", errors="replace") as fh:
                    payload = fh.readline().rstrip("\n")
            except OSError:
                print("job registry is unreadable")
                raise SystemExit(3)
            fields = payload.split("\t")
            run_dir = fields[0] if fields else ""
            exact_name = (
                name in handles
                or name in {sig, sig8, task_id, f"codex-lead-{sig8}"}
                or name.endswith(f"-{sig8}")
            )
            exact_payload = (
                task_id in fields[3:]
                or os.path.basename(run_dir.rstrip("/")) in {task_id, f"dispatch-{sig8}"}
                or f"/.claude/worktrees/{task_id}" in run_dir
                or f"/dispatch-{sig8}/" in f"{run_dir}/"
            )
            if exact_name or exact_payload:
                print(f"job registry has live handle {name} for signature {sig8}")
                raise SystemExit(2)
    except OSError:
        print("job registry is unreadable")
        raise SystemExit(3)

if active and os.path.exists(active):
    try:
        import yaml
        with open(active, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        for row in data.get("sessions", []):
            if str(row.get("task_id") or "") not in {task_id, sig8, f"dispatch-{sig8}"}:
                continue
            status = str(row.get("status") or "").lower()
            if status in {"finished", "complete", "completed", "dead", "closed"}:
                continue
            pid = row.get("pid")
            live = False
            try:
                os.kill(int(pid), 0)
                live = True
            except (TypeError, ValueError, ProcessLookupError):
                live = False
            except PermissionError:
                live = True
            if live or not pid:
                print(f"active registry has a live claim for task {task_id}")
                raise SystemExit(2)
    except OSError:
        print("active registry is unreadable")
        raise SystemExit(3)

raise SystemExit(0)
PYEOF
)"
_guard_rc=$?
set -e
if [[ $_guard_rc -ne 0 ]]; then
  refuse "${_guard_reason:-duplicate guard could not be evaluated}"
fi

_runner_pid_file="$PROJECT_ROOT/docs/handoff/$TASK_ID/.session-runner.pid"
if [[ -f "$_runner_pid_file" ]]; then
  _runner_pid="$(tr -d '[:space:]' < "$_runner_pid_file" 2>/dev/null || true)"
  if [[ "$_runner_pid" =~ ^[0-9]+$ ]] && kill -0 "$_runner_pid" 2>/dev/null; then
    refuse "live runner pid $_runner_pid already owns task $TASK_ID"
  fi
fi

CLAIMED=0
WORKTREE_CREATED=0
WORKTREE=""
REGISTRY_ENTRY=""
HANDOFF_COMPLETE=0
HANDOFF_DIR_CREATED=0
LOG_CREATED=0

# shellcheck disable=SC2329  # invoked indirectly by the EXIT trap
_cleanup_failure() {
  _cleanup_rc=$?
  if [[ "$HANDOFF_COMPLETE" -eq 0 ]]; then
    set +e
    [[ -z "$REGISTRY_ENTRY" ]] || rm -f -- "$REGISTRY_ENTRY" 2>/dev/null
    if [[ "$WORKTREE_CREATED" -eq 1 ]]; then
      git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
      git -C "$PROJECT_ROOT" worktree prune >/dev/null 2>&1 || true
      git -C "$PROJECT_ROOT" branch -D "$TASK_BRANCH" >/dev/null 2>&1 || true
    fi
    if [[ "$CLAIMED" -eq 1 ]]; then
      leadv2_tasks_unclaim "$TASK_ID" >/dev/null 2>&1 || true
    fi
    if [[ "$LOG_CREATED" -eq 1 ]]; then
      rm -f -- "$RUNNER_LOG" 2>/dev/null || true
    fi
    if [[ "$HANDOFF_DIR_CREATED" -eq 1 ]]; then
      rmdir "$PROJECT_ROOT/docs/handoff/$TASK_ID" 2>/dev/null || true
    fi
    set -e
  fi
  return "$_cleanup_rc"
}
trap _cleanup_failure EXIT

CLAIM_OWNER="codex-lead:${SIG8}:$$"
if ! leadv2_tasks_claim "$TASK_ID" --by "$CLAIM_OWNER" >/dev/null 2>&1; then
  refuse "task $TASK_ID could not be claimed"
fi
CLAIMED=1

_existing_worktree="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" \
  "$LANE_WORKTREE_BIN" path-of "$TASK_ID" 2>/dev/null || true)"
WORKTREE="$(LEADV2_PROJECT_ROOT="$PROJECT_ROOT" \
  LEADV2_LANE_BASE="${LEADV2_CODEX_LEAD_WORKTREE_BASE:-${LEADV2_LANE_BASE:-}}" \
  "$LANE_WORKTREE_BIN" ensure "$TASK_ID")"
[[ -n "$WORKTREE" && -d "$WORKTREE" ]] || refuse "lane worktree helper returned no usable path for task $TASK_ID"
if [[ -z "$_existing_worktree" && "$WORKTREE" != "$PROJECT_ROOT" ]]; then
  WORKTREE_CREATED=1
fi

_handoff_dir="$PROJECT_ROOT/docs/handoff/$TASK_ID"
if [[ ! -d "$_handoff_dir" ]]; then
  HANDOFF_DIR_CREATED=1
fi
mkdir -p "$_handoff_dir" 2>/dev/null || refuse 'could not create runner handoff directory'
if [[ ! -e "$RUNNER_LOG" ]]; then
  LOG_CREATED=1
fi
: >> "$RUNNER_LOG" || refuse 'could not create runner log'

_registry_dir="$JOB_REGISTRY_ROOT/codex-lead-terminal"
if ! mkdir -p "$_registry_dir" 2>/dev/null; then
  refuse 'could not create job registry entry'
fi
RUNNER_HANDLE="codex-lead-$SIG8"
REGISTRY_ENTRY="$_registry_dir/$RUNNER_HANDLE"
if ! printf -- '%s\t%s\t%s\t%s\n' "$WORKTREE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" codex-lead "$TASK_ID" > "$REGISTRY_ENTRY" 2>/dev/null; then
  refuse 'could not create job registry entry'
fi

nohup env LEADV2_CODEX_LEAD_INTERNAL=1 \
  bash "$SCRIPT_DIR/leadv2-codex-lead.sh" --run-detached \
    "$REGISTRY_ENTRY" "$RUNNER_BIN" "$TASK_ID" "$PROJECT_ROOT" "$WORKTREE" \
    >> "$RUNNER_LOG" 2>&1 </dev/null &
RUNNER_PID=$!
[[ "$RUNNER_PID" =~ ^[0-9]+$ ]] || refuse 'session runner did not return a process handle'

HANDOFF_COMPLETE=1
printf -- 'chosen task: %s (signature=%s)\n' "$TASK_ID" "$SIG8"
printf -- 'worktree: %s\n' "$WORKTREE"
printf -- 'runner handle: %s (pid=%s)\n' "$RUNNER_HANDLE" "$RUNNER_PID"
printf -- 'runner log: %s\n' "$RUNNER_LOG"
printf -- 'relay wake-point: Gate-1\n'
printf -- 'relay wake-point: async question\n'
printf -- 'relay wake-point: Phase-8 close (validate sentinel receipt + commit ancestry; lead climbs the live ladder)\n'
printf -- 'relay sentinel (shared root): %s\n' "$PROJECT_ROOT/docs/handoff/$TASK_ID/phase8-passed.flag"
printf -- 'relay sentinel (worktree mirror): %s\n' "$WORKTREE/docs/handoff/$TASK_ID/phase8-passed.flag"

exit 0
