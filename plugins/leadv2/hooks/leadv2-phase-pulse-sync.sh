#!/usr/bin/env bash
# leadv2-phase-pulse-sync.sh — PostToolUse:Write hook (LEAD-ANCHOR-01).
#
# Enforcement point for phase/pulse write-back: a prompt instruction alone
# was not a fix (subagents never remembered to call phase-advance.sh; 3
# fanned-out sessions sat at phase=spawning for 65+ min while deep in the
# pipeline). This hook fires automatically whenever ANY session (lead or
# subagent, in its own worktree) writes a deliverable file — which IS every
# phase boundary — and best-effort calls leadv2-phase-advance.sh so it can
# write phase/last_pulse_at back to the control-plane active.yaml.
#
# Matcher (registered in settings.json): Write tool, tool_input.file_path
# matching docs/handoff/<task_id>/*.summary.md or *.full.md or context.yaml.
#
# Never blocks the tool call: always exits 0. Missing task_id, missing
# scripts, or a write to any other path are silent no-ops.

set -euo pipefail

PAYLOAD="$(cat)"
FILE_PATH="$(printf -- '%s' "$PAYLOAD" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("file_path", ""))
except Exception:
    print("")
' 2>/dev/null || true)"

[[ -z "$FILE_PATH" ]] && exit 0
[[ "$FILE_PATH" == *"/docs/handoff/"* ]] || exit 0

# Extract <task_id> from .../docs/handoff/<task_id>/<anything>
TASK_ID="$(printf -- '%s' "$FILE_PATH" | sed -n 's#.*/docs/handoff/\([^/]*\)/.*#\1#p')"
[[ -z "$TASK_ID" ]] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ADVANCE_SH="${PROJECT_ROOT}/.claude/scripts/leadv2-phase-advance.sh"
[[ -x "$ADVANCE_SH" || -f "$ADVANCE_SH" ]] || exit 0

PROJECT_ROOT="$PROJECT_ROOT" bash "$ADVANCE_SH" --task-id "$TASK_ID" >/dev/null 2>&1 || true

exit 0
