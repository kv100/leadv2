#!/usr/bin/env bash
# Stop hook — IDLE-LEAD-GUARD-01: refuse turn end while work is queued and
# no lane is live.
#
# Block condition (ALL must hold):
#   (a) docs/tasks.yaml has ≥1 row with status ∈ {queued,ready,pending}
#   (b) leadv2-lane-liveness.sh --all --json reports availability=authoritative
#       and count_live==0
#   (c) no founder question has status=="pending"
#   (d) no docs/leadv2/session-goal.yaml is present with an unsatisfied
#       done_when (see IDLE-LEAD-GUARD-01 fix round 2, §5.1)
#
# If all hold, emits {"decision":"block","reason":"…"} on stdout to hold the
# turn open and guide the lead to dispatch the next task.
#
# Owns its iteration cap (per-session counter file), default 8 consecutive
# blocks, so the lead is never wedged. All error paths exit 0 with no output
# (fail-open). Governing rule for every branch: when in doubt, allow the stop.
#
# Kill switch: LEADV2_IDLE_GUARD=0 disables entirely.
# Rollback:    remove this entry from hooks.Stop[0].hooks[] in hooks.json.
#
# R6: only fires inside a leadv2 project (docs/leadv2/ + docs/tasks.yaml).
# R4: any error, unparseable input, missing file → exit 0, no output.
# R7: stop_hook_active is emitted in the stderr diagnostic line on every
#     allow/block, never read for control flow.

set -euo pipefail
trap 'exit 0' ERR

# --- kill switch (R5) ---------------------------------------------------------
[[ "${LEADV2_IDLE_GUARD:-1}" == "1" ]] || exit 0

# --- read stdin ---------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Parse session_id, cwd and stop_hook_active from Stop-hook stdin JSON (fail-open).
META="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
except Exception:
    r = {}
print(r.get("session_id", "") or "")
print(r.get("cwd", "") or "")
print("true" if r.get("stop_hook_active", False) else "false")
' 2>/dev/null || true)"

SESSION_ID="$(printf '%s' "$META" | sed -n '1p')"
CWD="$(printf '%s' "$META" | sed -n '2p')"
STOP_HOOK_ACTIVE="$(printf '%s' "$META" | sed -n '3p')"
[[ -n "$STOP_HOOK_ACTIVE" ]] || STOP_HOOK_ACTIVE="false"

[[ -n "$SESSION_ID" ]] || exit 0
[[ -n "$CWD" ]] || exit 0

# --- project scoping (R6) -----------------------------------------------------
PROJECT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"

if [[ ! -d "$PROJECT_ROOT/docs/leadv2" ]]; then exit 0; fi
if [[ ! -f "$PROJECT_ROOT/docs/tasks.yaml" ]]; then exit 0; fi

# --- config -------------------------------------------------------------------
CAP="${LEADV2_IDLE_GUARD_MAX_BLOCKS:-8}"
STATUSES_RAW="${LEADV2_IDLE_GUARD_STATUSES:-queued,ready,pending}"
STATE_DIR="${LEADV2_IDLE_GUARD_STATE_DIR:-$HOME/.claude}"
TASKS_FILE_OVERRIDE="${LEADV2_IDLE_GUARD_TASKS_FILE:-}"
LIVENESS_SH="${LEADV2_IDLE_GUARD_LIVENESS_SH:-}"
QUESTIONS_DIR_OVERRIDE="${LEADV2_IDLE_GUARD_QUESTIONS_DIR:-}"
COUNTER_TTL_S="${LEADV2_IDLE_GUARD_COUNTER_TTL_S:-3600}"
GOAL_FILE="${LEADV2_IDLE_GUARD_GOAL_FILE:-$PROJECT_ROOT/docs/leadv2/session-goal.yaml}"

COUNTER_FILE="${STATE_DIR}/leadv2-idle-guard-${SESSION_ID}.count"

# --- iteration cap (R3) — check BEFORE expensive probes -----------------------
# F4: a counter older than the TTL is treated as stale (count=0) rather than
# carried forward forever. Any failure reading the age → treat as fresh (keep
# counting toward the cap — the conservative direction is to keep counting,
# not to silently reset it).
count=0
if [[ -f "$COUNTER_FILE" ]]; then
  age="$(python3 -c '
import os, sys, time
try:
    print(int(time.time() - os.path.getmtime(sys.argv[1])))
except Exception:
    print(-1)
' "$COUNTER_FILE" 2>/dev/null || printf -- '-1')"
  case "$age" in
    ''|*[!0-9-]*) age=-1 ;;
  esac
  if (( age >= 0 && age > COUNTER_TTL_S )); then
    count=0
  else
    count="$(cat "$COUNTER_FILE" 2>/dev/null || printf '0')"
    case "$count" in
      ''|*[!0-9]*) count=0 ;;
    esac
  fi
fi

if (( count >= CAP )); then
  printf 'IDLE-LEAD-GUARD: cap reached (%d/%s). Allowing stop. Set LEADV2_IDLE_GUARD=0 to disable. [stop_hook_active=%s]\n' "$count" "$CAP" "$STOP_HOOK_ACTIVE" >&2
  printf '0' > "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- helper: reset counter and allow -------------------------------------------
# F1/F2/F5.1 contract: allow_stop resets the counter best-effort (reset
# failure is harmless — it only ever costs one extra allowed stop, never a
# block), optionally prints a one-line stderr diagnostic naming why, and
# exits 0 with no stdout.
allow_stop() {
  local reason="${1:-}"
  printf '0' > "$COUNTER_FILE" 2>/dev/null || true
  if [[ -n "$reason" ]]; then
    printf '%s [stop_hook_active=%s]\n' "$reason" "$STOP_HOOK_ACTIVE" >&2
  fi
  exit 0
}

# --- F1 contract: a cap that cannot count must not block -----------------------
# Read-back verification (not just the write's rc) also covers a full disk, a
# truncated write, and a $COUNTER_FILE that exists but is an unreadable/
# foreign inode.
persist_count() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  printf '%s' "$1" > "$COUNTER_FILE" 2>/dev/null || return 1
  [[ "$(cat "$COUNTER_FILE" 2>/dev/null || true)" == "$1" ]] || return 1
}

# --- condition (c): pending founder question -----------------------------------
QDIR=""; QDIR_RESOLVED=0
if [[ -n "$QUESTIONS_DIR_OVERRIDE" ]]; then
  QDIR="$QUESTIONS_DIR_OVERRIDE"; QDIR_RESOLVED=1
else
  SP="$(dirname "$0")/../scripts/leadv2-state-path.sh"
  if [[ -f "$SP" ]]; then
    QDIR="$(timeout 4 bash "$SP" questions 2>/dev/null || true)"
  fi
  [[ -n "$QDIR" ]] && QDIR_RESOLVED=1
fi

(( QDIR_RESOLVED == 1 )) || allow_stop \
  "IDLE-LEAD-GUARD: questions dir unresolvable (leadv2-state-path.sh missing or failed) — cannot prove no question is pending, allowing stop."

if [[ -d "$QDIR" ]]; then
  # Scan for any question with status=="pending"; prints "yes <id>" or "no".
  has_pending_q="$(python3 -c '
import sys, os, glob, yaml
try:
    found_id = None
    for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.yaml"))):
        try:
            with open(p) as f:
                doc = yaml.safe_load(f)
            if isinstance(doc, dict) and doc.get("status") == "pending":
                found_id = os.path.splitext(os.path.basename(p))[0]
                break
        except Exception:
            continue
    print(("yes " + found_id) if found_id else "no")
except Exception:
    print("yes ?")  # fail-open: cannot prove no pending question
' "$QDIR" 2>/dev/null || printf 'yes ?')"
  if [[ "$has_pending_q" == yes* ]]; then
    qid="${has_pending_q#yes }"
    allow_stop "IDLE-LEAD-GUARD: founder question pending (${qid}) — allowing stop."
  fi
fi

# --- resolve the task store path (shared by (d) and (a)) -----------------------
TASKS_FILE="$TASKS_FILE_OVERRIDE"
if [[ -z "$TASKS_FILE" ]]; then
  # Source tasks-lib to get _TASKS_FILE (honours PROJECT_ROOT > git root > CLAUDE_PROJECT_DIR)
  LIB_SCRIPT="$(dirname "$0")/../scripts/leadv2-tasks-lib.sh"
  if [[ -f "$LIB_SCRIPT" ]]; then
    _idle_source_output="$(set +e; PROJECT_ROOT="$PROJECT_ROOT" source "$LIB_SCRIPT" 2>/dev/null; set -e; printf '%s' "${_TASKS_FILE:-}")"
    TASKS_FILE="$_idle_source_output"
  fi
  # Fallback to the conventional path
  [[ -n "$TASKS_FILE" ]] || TASKS_FILE="$PROJECT_ROOT/docs/tasks.yaml"
fi

# --- condition (d): declared session goal reached (F5.1) -----------------------
# Optional. Only three declarative predicate keys — no shell/command field.
# Unparseable file or an unknown predicate key → treated as satisfied (allow):
# a hook must never let a malformed goal file widen the block surface.
if [[ -f "$GOAL_FILE" ]]; then
  GOAL_RESULT="$(python3 -c '
import sys, yaml, os

goal_file, tasks_file, project_root = sys.argv[1], sys.argv[2], sys.argv[3]

def load_tasks(path):
    try:
        with open(path) as f:
            items = yaml.safe_load(f)
        if not isinstance(items, list):
            return []
        return [it for it in items if isinstance(it, dict)]
    except Exception:
        return []

try:
    with open(goal_file) as f:
        goal = yaml.safe_load(f)
    if not isinstance(goal, dict):
        print("yes unparseable")
        sys.exit(0)
except Exception:
    print("yes unparseable")
    sys.exit(0)

done_when = goal.get("done_when")
if not isinstance(done_when, dict):
    print("no -")
    sys.exit(0)

KNOWN = {"tasks_absent", "tasks_status", "file_exists"}
if not set(done_when.keys()) <= KNOWN:
    print("yes unknown-key")
    sys.exit(0)

tasks = load_tasks(tasks_file)
by_id = {}
for t in tasks:
    tid = str(t.get("id", "")).strip()
    if tid:
        by_id[tid] = str(t.get("status", "")).strip()

ok = True

if "tasks_absent" in done_when:
    absent_ids = done_when["tasks_absent"]
    if isinstance(absent_ids, list):
        for tid in absent_ids:
            if str(tid) in by_id:
                ok = False
                break

if ok and "tasks_status" in done_when:
    status_map = done_when["tasks_status"]
    if isinstance(status_map, dict):
        for tid, want in status_map.items():
            if by_id.get(str(tid)) != str(want):
                ok = False
                break

if ok and "file_exists" in done_when:
    rel = str(done_when["file_exists"])
    fpath = rel if os.path.isabs(rel) else os.path.join(project_root, rel)
    if not os.path.isfile(fpath):
        ok = False

goal_name = str(goal.get("goal", "")).strip() or "unnamed"
print(("yes " if ok else "no ") + goal_name)
' "$GOAL_FILE" "$TASKS_FILE" "$PROJECT_ROOT" 2>/dev/null || printf 'yes unparseable')"

  if [[ "$GOAL_RESULT" == yes* ]]; then
    goal_name="${GOAL_RESULT#yes }"
    allow_stop "IDLE-LEAD-GUARD: goal reached (\"${goal_name}\") — allowing stop."
  fi
fi

# --- condition (a): queued work -------------------------------------------------
[[ -f "$TASKS_FILE" ]] || allow_stop

# Scan tasks.yaml for rows matching the target statuses (file order preserved)
QUEUED_JSON="$(python3 -c '
import sys, yaml
statuses = set(s.strip() for s in sys.argv[1].split(",") if s.strip())
try:
    with open(sys.argv[2]) as f:
        items = yaml.safe_load(f)
    if not isinstance(items, list):
        items = []
except Exception:
    items = []
rows = []
for it in items:
    if not isinstance(it, dict):
        continue
    if str(it.get("status", "")).strip() in statuses:
        rows.append({
            "id": str(it.get("id", "")).strip(),
            "lane": str(it.get("lane", "")).strip(),
            "title": str(it.get("title", "")).strip(),
        })
import json
print(json.dumps(rows))
' "$STATUSES_RAW" "$TASKS_FILE" 2>/dev/null || printf '[]')"

QUEUED_COUNT="$(printf '%s' "$QUEUED_JSON" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())))' 2>/dev/null || printf '0')"

(( QUEUED_COUNT > 0 )) || allow_stop

# --- condition (b): zero live lanes -------------------------------------------
if [[ -z "$LIVENESS_SH" ]]; then
  LIVENESS_SH="$(dirname "$0")/../scripts/leadv2-lane-liveness.sh"
fi

[[ -x "$LIVENESS_SH" || -f "$LIVENESS_SH" ]] || allow_stop

LIVENESS_RAW="$(timeout 4 bash "$LIVENESS_SH" --all --json --project-root "$PROJECT_ROOT" 2>/dev/null || true)"
[[ -n "$LIVENESS_RAW" ]] || allow_stop

LIVENESS_PARSED="$(printf '%s' "$LIVENESS_RAW" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(d.get("availability",""))
    print(str(d.get("count_live", -1)))
except Exception:
    print("")
    print("")
' 2>/dev/null || true)"

L_AVAIL="$(printf '%s' "$LIVENESS_PARSED" | sed -n '1p')"
L_COUNT="$(printf '%s' "$LIVENESS_PARSED" | sed -n '2p')"

# availability must be authoritative; otherwise cannot prove zero live
[[ "$L_AVAIL" == "authoritative" ]] || allow_stop
case "$L_COUNT" in
  ''|*[!0-9]*) allow_stop ;;
esac
(( L_COUNT == 0 )) || allow_stop

# --- BLOCK (R2) ---------------------------------------------------------------
# F1: increment the counter — if it cannot be durably persisted, the cap can
# never count, so allow the stop instead of blocking forever.
new_count=$(( count + 1 ))
if ! persist_count "$new_count"; then
  allow_stop "IDLE-LEAD-GUARD: counter not persistable at ${COUNTER_FILE} — cap cannot count, allowing stop."
fi

printf 'IDLE-LEAD-GUARD: blocking (%d/%s) [stop_hook_active=%s]\n' "$new_count" "$CAP" "$STOP_HOOK_ACTIVE" >&2

# Build the reason: name the first queued task as the next action
REASON="$(printf '%s' "$QUEUED_JSON" | python3 -c '
import sys, json

rows = json.loads(sys.stdin.read())
cap = int(sys.argv[1])
max_blocks = int(sys.argv[2])
count = len(rows)

first = rows[0]
first_id = first.get("id", "?")
first_title = first.get("title", "")
if len(first_title) > 60:
    first_title = first_title[:57] + "..."
first_title = first_title.replace("\n", " ").replace("\r", "")

others = ", ".join(r.get("id","?") for r in rows[1:4])
others_str = f" Other queued: {others}." if others else ""

reason = (
    f"IDLE-LEAD-GUARD: {count} queued row(s), 0 live lanes, no pending question. "
    f"Next: dispatch {first_id} ({first_title}).{others_str} "
    f"Cap: {cap}/{max_blocks}. Kill: LEADV2_IDLE_GUARD=0."
)
# Output as JSON string value (safe for embedding in the decision JSON)
print(json.dumps({"decision": "block", "reason": reason}))
' "$new_count" "$CAP" 2>/dev/null || true)"

[[ -n "$REASON" ]] || allow_stop

printf '%s\n' "$REASON"
exit 0
