#!/usr/bin/env bash
# lane-lesson-capture-hook.sh — PostToolUse:Bash hook (SELF-LEARNING-IS-EMPTY-01).
#
# Detects a lane-close commit (git commit whose message mentions a dispatch
# sig8 or a founder task id) and fires scripts/lane-lesson-capture.sh in the
# background so a lesson gets captured on the path dispatch lanes actually
# use, without anyone remembering to run the Phase-8 close skill.
#
# Never blocks the tool call and never fails it: always exits 0. A broken
# capture must never break a commit.

set -euo pipefail
trap 'exit 0' ERR

PAYLOAD="$(cat)"

CMD="$(printf -- '%s' "$PAYLOAD" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command", ""))
except Exception:
    print("")
' 2>/dev/null || true)"
[[ -z "$CMD" ]] && exit 0

# Only act on git commit (incl. --amend).
case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Only act on a successful tool call.
IS_ERROR="$(printf -- '%s' "$PAYLOAD" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print("1" if (d.get("tool_response") or {}).get("is_error") else "0")
except Exception:
    print("0")
' 2>/dev/null || echo "0")"
[[ "$IS_ERROR" == "1" ]] && exit 0

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CAPTURE_BIN="${PROJECT_ROOT}/scripts/lane-lesson-capture.sh"
[[ -x "$CAPTURE_BIN" ]] || exit 0

# Extract a dispatch sig8 (hex-8, `dispatch-xxxxxxxx`) or a founder task id
# shape (LETTER + [A-Z0-9-]{6,} + -NN) from the commit message.
TASK_ID="$(printf -- '%s' "$CMD" | grep -oE 'dispatch-[0-9a-f]{8}' | head -1 || true)"
if [[ -z "$TASK_ID" ]]; then
  TASK_ID="$(printf -- '%s' "$CMD" | grep -oE '[A-Z][A-Z0-9-]{6,}-[0-9]{2}' | head -1 || true)"
fi
[[ -z "$TASK_ID" ]] && exit 0

( timeout 90 "$CAPTURE_BIN" --task "$TASK_ID" >/dev/null 2>&1 & ) || true

exit 0
