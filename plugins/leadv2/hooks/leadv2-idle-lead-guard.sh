#!/usr/bin/env bash
# Stop hook — IDLE-LEAD-GUARD-01: refuse turn end while work is queued and
# no lane is live.
#
# Block condition (ALL must hold):
#   (a) docs/tasks.yaml has ≥1 row with status ∈ {queued,ready,pending}
#   (b) leadv2-lane-liveness.sh --all --json reports availability=authoritative
#       and count_live==0
#   (c) no founder question has status=="pending"
#
# If all three hold, emits {"decision":"block","reason":"…"} on stdout to
# hold the turn open and guide the lead to dispatch the next task.
#
# Owns its iteration cap (per-session counter file), default 8 consecutive
# blocks, so the lead is never wedged. All error paths exit 0 with no output
# (fail-open).
#
# Kill switch: LEADV2_IDLE_GUARD=0 disables entirely.
# Rollback:    remove this entry from hooks.Stop[0].hooks[] in hooks.json.
#
# R6: only fires inside a leadv2 project (docs/leadv2/ + docs/tasks.yaml).
# R4: any error, unparseable input, missing file → exit 0, no output.
# R7: stop_hook_active is read for telemetry only, never for control flow.

set -euo pipefail
trap 'exit 0' ERR

# --- kill switch (R5) ---------------------------------------------------------
[[ "${LEADV2_IDLE_GUARD:-1}" == "1" ]] || exit 0

# --- read stdin ---------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Parse session_id and cwd from Stop-hook stdin JSON (fail-open).
META="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
except Exception:
    r = {}
print(r.get("session_id", "") or "")
print(r.get("cwd", "") or "")
' 2>/dev/null || true)"

SESSION_ID="$(printf '%s' "$META" | sed -n '1p')"
CWD="$(printf '%s' "$META" | sed -n '2p')"

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

COUNTER_FILE="${STATE_DIR}/leadv2-idle-guard-${SESSION_ID}.count"

# --- iteration cap (R3) — check BEFORE expensive probes -----------------------
count=0
if [[ -f "$COUNTER_FILE" ]]; then
  count="$(cat "$COUNTER_FILE" 2>/dev/null || printf '0')"
  case "$count" in
    ''|*[!0-9]*) count=0 ;;
  esac
fi

if (( count >= CAP )); then
  printf 'IDLE-LEAD-GUARD: cap reached (%d/%s). Allowing stop. Set LEADV2_IDLE_GUARD=0 to disable.\n' "$count" "$CAP" >&2
  printf '0' > "$COUNTER_FILE" 2>/dev/null || true
  exit 0
fi

# --- helper: reset counter and allow -----------------------------------------
allow_stop() {
  printf '0' > "$COUNTER_FILE" 2>/dev/null || true
  exit 0
}

# --- condition (c): pending founder question ---------------------------------
QDIR=""
if [[ -n "$QUESTIONS_DIR_OVERRIDE" ]]; then
  QDIR="$QUESTIONS_DIR_OVERRIDE"
else
  QDIR="$("$(dirname "$0")/../scripts/leadv2-state-path.sh" questions 2>/dev/null || true)"
fi

if [[ -n "$QDIR" && -d "$QDIR" ]]; then
  # Scan for any question with status=="pending"
  has_pending_q="$(python3 -c '
import sys, os, glob, yaml
try:
    found = False
    for p in glob.glob(os.path.join(sys.argv[1], "*.yaml")):
        try:
            with open(p) as f:
                doc = yaml.safe_load(f)
            if isinstance(doc, dict) and doc.get("status") == "pending":
                found = True
                break
        except Exception:
            continue
    print("yes" if found else "no")
except Exception:
    print("yes")  # fail-open: cannot prove no pending question
' "$QDIR" 2>/dev/null || printf 'yes')"
  [[ "$has_pending_q" == "yes" ]] && allow_stop
fi

# --- condition (a): queued work -----------------------------------------------
# Resolve the task store path
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
# Increment the counter
new_count=$(( count + 1 ))
printf '%s' "$new_count" > "$COUNTER_FILE" 2>/dev/null || true

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
