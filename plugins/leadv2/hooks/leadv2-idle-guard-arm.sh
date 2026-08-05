#!/usr/bin/env bash
# SessionStart hook — IDLE-LEAD-GUARD-01 fix round 2, §5.2: self-arms the
# idle-lead-guard Stop hook for the new session.
#
# All steps best-effort, exit 0 unconditionally — this hook must never block
# session start. Honours LEADV2_IDLE_GUARD=0 (same kill switch as the Stop
# hook).
#
# 1. Fresh session → fresh cap budget: remove this session's counter file.
# 2. Reap stale counter files older than 24h (F4 companion to the Stop
#    hook's TTL-based stale-count read).
# 3. If docs/leadv2/session-goal.yaml exists and parses, surface it via
#    additionalContext so the first turn knows the session is armed and what
#    ends the loop.
#
# Rollback: remove this entry from hooks.SessionStart[0].hooks[] in
# hooks.json; delete this file.

set -uo pipefail
trap 'exit 0' ERR

# --- kill switch ----------------------------------------------------------
[[ "${LEADV2_IDLE_GUARD:-1}" == "1" ]] || exit 0

# --- read stdin -------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

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

# --- project scoping (same gate as the Stop hook) ---------------------------
PROJECT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"

if [[ ! -d "$PROJECT_ROOT/docs/leadv2" ]]; then exit 0; fi
if [[ ! -f "$PROJECT_ROOT/docs/tasks.yaml" ]]; then exit 0; fi

STATE_DIR="${LEADV2_IDLE_GUARD_STATE_DIR:-$HOME/.claude}"
GOAL_FILE="${LEADV2_IDLE_GUARD_GOAL_FILE:-$PROJECT_ROOT/docs/leadv2/session-goal.yaml}"

# --- step 1: fresh cap budget for this session -------------------------------
rm -f "${STATE_DIR}/leadv2-idle-guard-${SESSION_ID}.count" 2>/dev/null || true

# --- step 2: reap 24h-stale counter files ------------------------------------
# Glob anchored to the literal prefix/suffix — never a bare "*".
if [[ -d "$STATE_DIR" ]]; then
  find "$STATE_DIR" -maxdepth 1 -type f -name 'leadv2-idle-guard-*.count' -mtime +1 -exec rm -f {} + 2>/dev/null || true
fi

# --- step 3: emit armed context if a session goal is declared ---------------
if [[ -f "$GOAL_FILE" ]]; then
  GOAL_NAME="$(python3 -c '
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        goal = yaml.safe_load(f)
    if isinstance(goal, dict):
        name = str(goal.get("goal", "")).strip()
        if name:
            print(name)
except Exception:
    pass
' "$GOAL_FILE" 2>/dev/null || true)"

  if [[ -n "$GOAL_NAME" ]]; then
    python3 -c '
import json, sys
goal = sys.argv[1]
ctx = (
    "IDLE-LEAD-GUARD armed. Session goal: " + goal + ". "
    "The turn will be held open while work is queued and no lane is live; "
    "it is released when the goal'"'"'s done_when is satisfied, or at 8 "
    "consecutive blocks."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}))
' "$GOAL_NAME" 2>/dev/null || true
  fi
fi

exit 0
