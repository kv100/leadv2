#!/usr/bin/env bash
# scripts/leadv2-merge-queue.sh — LEAD-BUS-01 FIFO merge serialization.
#
# Event-sourced ledger at docs/leadv2/merge-queue.jsonl, all mutations under
# a python3 fcntl.flock(LOCK_EX) critical section on docs/leadv2/.merge.lock
# (same locking primitive proven on darwin by scripts/leadv2-bus.sh /
# tests/leadv2/test-bus.sh). Current holder + waiting order are DERIVED by
# replaying the ledger — no separate mutable state file to fall out of sync.
#
# Usage:
#   leadv2-merge-queue.sh enqueue <task-id> <branch>
#   leadv2-merge-queue.sh acquire <task-id>     # blocks until it's this
#                                                 # task's turn; exit 2 on
#                                                 # 30-min timeout (circuit
#                                                 # breaker for Phase 6)
#   leadv2-merge-queue.sh release <task-id>
#   leadv2-merge-queue.sh status
#
# Dead-holder reclaim: if the current holder's pid is not alive AND it has
# held the lock for > LEADV2_MERGE_STALE_SEC (default 600s = 10min), the
# next `acquire` poll reclaims it (emits a `reclaimed` ledger event AND a
# `finding` event on the bus via leadv2-bus.sh) and the queue proceeds.
#
# Env overrides (tests sandbox / speed up polling):
#   PROJECT_ROOT              - repo root
#   LEADV2_DIR                - dir holding merge-queue.jsonl / .merge.lock
#                                (default: LEAD-CONTROL-PLANE-01 control-plane
#                                root, resolved via leadv2-state-path.sh —
#                                OUTSIDE any git worktree. Never hardcode
#                                docs/leadv2 here: each worktree used to get
#                                its own private lock, admitting every
#                                acquirer instead of serializing them.)
#   LEADV2_MERGE_POLL_SEC     - poll interval while blocked (default 0.5)
#   LEADV2_MERGE_TIMEOUT_SEC  - acquire timeout (default 1800 = 30min)
#   LEADV2_MERGE_STALE_SEC    - dead-holder reclaim threshold (default 600)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# --no-link: this call only wants a directory location for merge-queue.jsonl
# / .merge.lock, never docs/leadv2/* symlink repair (that's this script's own
# business, not merge-queue's) -- and --no-link also skips state-path.sh's
# LEADV2_STATE_ROOT-set-but-real-repo B1 safety-net ABORT, which is otherwise
# unavoidable for any hermetic test sandbox that legitimately configures a
# git remote (needed to simulate a push/pull race) while sandboxing the
# control plane via LEADV2_STATE_ROOT (N-4 root-cause-B).
LEADV2_DIR="${LEADV2_DIR:-$("${SCRIPT_DIR}/leadv2-state-path.sh" --no-link)}"
QUEUE_FILE="${LEADV2_DIR}/merge-queue.jsonl"
QUEUE_LOCK="${LEADV2_DIR}/.merge.lock"
BUS_SH="${SCRIPT_DIR}/leadv2-bus.sh"

POLL_SEC="${LEADV2_MERGE_POLL_SEC:-0.5}"
TIMEOUT_SEC="${LEADV2_MERGE_TIMEOUT_SEC:-1800}"
STALE_SEC="${LEADV2_MERGE_STALE_SEC:-600}"
# The pid recorded as "holder" MUST be the long-lived caller (the Phase 6
# script that wraps acquire..release around its work), not this short-lived
# subprocess ($$ here dies the instant acquire returns). $PPID is that
# caller's real pid when this script is exec'd directly in the foreground
# (the normal case); override via LEADV2_MERGE_OWNER_PID if the real caller
# is further up the process tree (e.g. wrapped in a helper function/subshell).
OWNER_PID="${LEADV2_MERGE_OWNER_PID:-$PPID}"

mkdir -p "$LEADV2_DIR"

usage() {
  printf -- 'Usage:\n' >&2
  printf -- '  leadv2-merge-queue.sh enqueue <task-id> <branch>\n' >&2
  printf -- '  leadv2-merge-queue.sh acquire <task-id>\n' >&2
  printf -- '  leadv2-merge-queue.sh release <task-id>\n' >&2
  printf -- '  leadv2-merge-queue.sh status\n' >&2
  exit 1
}

# One transaction: replay ledger under flock, let the python snippet decide
# what (if anything) to append, then unlock. `$1` selects the operation.
_txn() {
  python3 - "$QUEUE_FILE" "$QUEUE_LOCK" "$STALE_SEC" "$@" <<'PYEOF'
import calendar, fcntl, json, os, sys, time

queue_file, queue_lock, stale_sec = sys.argv[1], sys.argv[2], float(sys.argv[3])
op = sys.argv[4]
args = sys.argv[5:]

def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def read_events():
    if not os.path.exists(queue_file):
        return []
    out = []
    with open(queue_file, encoding="utf-8") as f:
        for l in f:
            l = l.strip()
            if not l:
                continue
            try:
                out.append(json.loads(l))
            except Exception:
                continue
    return out

def append_event(ev):
    with open(queue_file, "a", encoding="utf-8") as f:
        f.write(json.dumps(ev, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())

def replay(events):
    queue = []          # waiting task_ids, FIFO order
    holder = None        # task_id currently holding, or None
    holder_ev = None
    enq_ev = {}           # task_id -> last "enqueued" event, for tasks still in queue
    for ev in events:
        t = ev.get("type")
        tid = ev.get("task_id")
        if t == "enqueued":
            if tid != holder and tid not in queue:
                queue.append(tid)
            enq_ev[tid] = ev
        elif t == "acquired":
            holder = tid
            holder_ev = ev
            if tid in queue:
                queue.remove(tid)
            enq_ev.pop(tid, None)
        elif t == "re-enqueued":
            # Refreshes the pid/ts of an existing queue row in place (the
            # caller re-ran acquire after its earlier process died) without
            # changing FIFO position and without going through "enqueued"
            # (which is a no-op once tid is already in queue).
            if tid in queue:
                enq_ev[tid] = ev
        elif t in ("released", "reclaimed", "timeout"):
            if holder == tid:
                holder = None
                holder_ev = None
            if tid in queue:
                queue.remove(tid)
            enq_ev.pop(tid, None)
    return queue, holder, holder_ev, enq_ev

def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False

def event_age_sec(ev):
    ts = ev.get("ts", "")
    try:
        since = calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
        return time.time() - since
    except Exception:
        return 0

lockf = open(queue_lock, "a+")
fcntl.flock(lockf, fcntl.LOCK_EX)
try:
    events = read_events()
    queue, holder, holder_ev, enq_ev = replay(events)

    if op == "enqueue":
        task_id, branch, caller_pid = args[0], args[1], args[2]
        if task_id != holder and task_id not in queue:
            append_event({
                "ts": now_iso(), "type": "enqueued",
                "task_id": task_id, "branch": branch, "pid": int(caller_pid),
            })
        elif task_id != holder and task_id in queue:
            # Idempotent re-run of `acquire` (e.g. after a crash/re-dispatch):
            # the task is already in the queue under a stale pid. Refresh
            # pid/ts in place, keeping FIFO position, so the dead-enqueued
            # reclaim below (which only ever looks at OTHER tasks' rows) does
            # not see a dead pid for this task on the very next try_acquire
            # (MERGE-QUEUE-DEAD-HEAD-01 round 2: reclaim was evicting the
            # caller's own row).
            prev = enq_ev.get(task_id)
            if prev is None or int(prev.get("pid", -1)) != int(caller_pid):
                append_event({
                    "ts": now_iso(), "type": "re-enqueued",
                    "task_id": task_id, "branch": branch, "pid": int(caller_pid),
                })
        print("OK")

    elif op == "try_acquire":
        reclaimed = False
        caller_task_id = args[0]

        # Reclaim dead+stale ENQUEUED entries first, before computing the
        # head (MERGE-QUEUE-DEAD-HEAD-01: an entry that never got past
        # `enqueued` because its owning process died was never examined by
        # the dead-holder-only reclaim below, so a dead task's enqueue sat
        # as a permanent head and every later acquire() printed WAIT
        # forever). Same threshold (STALE_SEC) and same ledger event shape
        # (`reclaimed`) as the dead-holder-stale reclaim, distinguished by
        # reason.
        #
        # The caller's OWN row is never reclaimed here (round 2 fix): a
        # re-dispatched task re-running `acquire` after a crash re-enqueues
        # under a new pid via the `enqueue` op above (see "re-enqueued"),
        # so by the time we get here its row already carries the live pid.
        # Excluding it defensively means a stale snapshot can never evict
        # the caller mid-poll and force it to restart at the back of the
        # queue / TIMEOUT.
        for tid in list(queue):
            if tid == caller_task_id:
                continue
            ev = enq_ev.get(tid)
            if ev is None:
                continue
            if not pid_alive(ev.get("pid")) and event_age_sec(ev) > stale_sec:
                append_event({
                    "ts": now_iso(), "type": "reclaimed",
                    "task_id": tid, "reason": "dead-enqueued",
                })
                reclaimed = True
        if reclaimed:
            events = read_events()
            queue, holder, holder_ev, enq_ev = replay(events)

        # Reclaim a dead+stale holder, if any.
        if holder is not None and holder_ev is not None:
            holder_pid = holder_ev.get("pid")
            holder_ts = holder_ev.get("ts", "")
            try:
                held_since = calendar.timegm(time.strptime(holder_ts, "%Y-%m-%dT%H:%M:%SZ"))
                age = time.time() - held_since
            except Exception:
                age = 0
            if not pid_alive(holder_pid) and age > stale_sec:
                append_event({
                    "ts": now_iso(), "type": "reclaimed",
                    "task_id": holder, "reason": "dead-holder-stale",
                })
                reclaimed = True
                events = read_events()
                queue, holder, holder_ev, enq_ev = replay(events)

        task_id, caller_pid = args[0], args[1]
        if holder is None and queue and queue[0] == task_id:
            append_event({
                "ts": now_iso(), "type": "acquired",
                "task_id": task_id, "pid": int(caller_pid),
            })
            print("ACQUIRED")
        else:
            print("RECLAIMED" if reclaimed else "WAIT")

    elif op == "release":
        task_id = args[0]
        if holder != task_id:
            sys.stderr.write(f"[merge-queue] {task_id} is not the current holder (holder={holder})\n")
            sys.exit(1)
        append_event({"ts": now_iso(), "type": "released", "task_id": task_id})
        print("OK")

    elif op == "timeout":
        task_id = args[0]
        append_event({"ts": now_iso(), "type": "timeout", "task_id": task_id})
        print("OK")

    elif op == "status":
        queue_view = []
        for tid in queue:
            ev = enq_ev.get(tid)
            state = "queued"
            if ev is not None and not pid_alive(ev.get("pid")) and event_age_sec(ev) > stale_sec:
                state = "DEAD-ENQUEUED"
            queue_view.append({"task_id": tid, "state": state})
        print(json.dumps({"holder": holder, "queue": queue_view}, sort_keys=True))

finally:
    fcntl.flock(lockf, fcntl.LOCK_UN)
    lockf.close()
PYEOF
}

[[ $# -ge 1 ]] || usage
CMD="$1"; shift

case "$CMD" in
  enqueue)
    [[ $# -eq 2 ]] || usage
    _txn enqueue "$1" "$2" "$OWNER_PID"
    ;;

  acquire)
    [[ $# -eq 1 ]] || usage
    TASK_ID="$1"
    _txn enqueue "$TASK_ID" "unknown" "$OWNER_PID" > /dev/null  # idempotent auto-enqueue
    SECONDS=0  # bash builtin: integer elapsed-seconds timer, reset here
    while true; do
      RESULT="$(_txn try_acquire "$TASK_ID" "$OWNER_PID")"
      if [[ "$RESULT" == "ACQUIRED" ]]; then
        exit 0
      fi
      if [[ "$RESULT" == "RECLAIMED" ]]; then
        # A stale holder was freed this poll — publish a bus finding so other
        # sessions see it, then re-poll immediately without sleeping.
        if [[ -x "$BUS_SH" ]]; then
          "$BUS_SH" publish "$TASK_ID" finding \
            '{"note":"merge-queue reclaimed a dead holder lock"}' 2>/dev/null || true
        fi
        continue
      fi
      if (( SECONDS > TIMEOUT_SEC )); then
        _txn timeout "$TASK_ID" "$OWNER_PID" > /dev/null
        printf -- '[merge-queue] acquire timeout after %ss for %s\n' "$TIMEOUT_SEC" "$TASK_ID" >&2
        exit 2
      fi
      sleep "$POLL_SEC"
    done
    ;;

  release)
    [[ $# -eq 1 ]] || usage
    _txn release "$1"
    ;;

  status)
    _txn status
    ;;

  *)
    usage
    ;;
esac
