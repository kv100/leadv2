#!/usr/bin/env bash
# SessionStart hook: instruct the sole main-checkout lead to arm its pulse watcher.
# This is best-effort and must never block session start.

set -uo pipefail
trap 'exit 0' ERR

[[ "${LEADV2_SINGLE_LEAD_BEAT:-1}" == "0" ]] && exit 0
[[ "${LEADV2_PULSE_WATCH:-1}" == "0" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

META="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print("yes" if "agent_type" in data else "no")
print(data.get("cwd", "") or "")
' 2>/dev/null || true)"
HAS_AGENT_TYPE="$(printf '%s' "$META" | sed -n '1p')"
CWD="$(printf '%s' "$META" | sed -n '2p')"
[[ "$HAS_AGENT_TYPE" != "yes" ]] || exit 0
[[ -n "$CWD" ]] || exit 0
[[ "$CWD" != *"/.claude/worktrees/"* ]] || exit 0

# shellcheck source=leadv2-mode-isolation.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-mode-isolation.sh"
leadv2_hook_is_supervisor_session "$INPUT" && exit 0

PROJECT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
[[ -d "$PROJECT_ROOT/docs/leadv2" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
CMD="$(CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}" bash "$SCRIPT_DIR/leadv2-pulse-watch.sh" --print 2>/dev/null || true)"
[[ -n "$CMD" ]] || exit 0

CONTEXT="PULSE-WAKE: arm the beat watcher NOW: Monitor(command=\"$CMD\", description=\"founder pulse beat\", persistent=true, timeout_ms=3600000). A lead session with no beat watcher armed is in violation — the 30-min founder status will not reach chat until the founder types. On a beat event, relay per the existing RELAY=full/none rules; do not compose a status yourself."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null || true
else
  python3 -c 'import json, sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$CONTEXT" 2>/dev/null || true
fi

exit 0
