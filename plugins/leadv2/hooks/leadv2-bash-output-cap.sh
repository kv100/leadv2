#!/usr/bin/env bash
# PostToolUse hook for Bash: cap oversized output BEFORE it enters the transcript.
#
# The previous version only warned on stderr, and it never even did that: it read
# `.tool_output` / `.tool_response.output`, neither of which is the key Claude Code
# actually sends, so SIZE was always 1 and the hook exited at the first guard. A
# warning is also the wrong instrument — the bytes are already in the transcript by
# the time the advice is printed, and the transcript is re-sent on every later turn.
#
# This version returns hookSpecificOutput.updatedToolOutput, which REPLACES the tool
# result the model sees. Full output is written to disk first and the replacement
# names the path, so nothing is lost and the lead can go read it deliberately.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

CAP_BYTES="${LEADV2_BASH_OUTPUT_CAP_BYTES:-12000}"
HEAD_BYTES="${LEADV2_BASH_OUTPUT_HEAD_BYTES:-7000}"
TAIL_BYTES="${LEADV2_BASH_OUTPUT_TAIL_BYTES:-3000}"
[[ "${LEADV2_BASH_OUTPUT_CAP:-1}" == "0" ]] && exit 0

# Claude Code sends Bash results under .tool_response; the historical keys are kept
# as fallbacks so this works if the shape differs across versions.
OUT="$(printf '%s' "$INPUT" | jq -r '
  (.tool_response.stdout? // empty) as $s
  | (.tool_response.stderr? // empty) as $e
  | if ($s|length) > 0 or ($e|length) > 0 then ($s + $e)
    else (.tool_response.output? // .tool_response? // .tool_output? // empty)
    end
  | if type == "string" then . else tostring end' 2>/dev/null || true)"

SIZE=${#OUT}
[[ "$SIZE" -le "$CAP_BYTES" ]] && exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | head -c 200 || true)"

SPILL_DIR="${TMPDIR:-/tmp}/leadv2-bash-spill"
mkdir -p "$SPILL_DIR"
SPILL="$SPILL_DIR/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM.txt"
printf '%s' "$OUT" > "$SPILL"

HEAD_PART="$(printf '%s' "$OUT" | head -c "$HEAD_BYTES")"
TAIL_PART="$(printf '%s' "$OUT" | tail -c "$TAIL_BYTES")"
ELIDED=$((SIZE - HEAD_BYTES - TAIL_BYTES))

NOTICE="

[leadv2-bash-output-cap] ${SIZE} bytes of output, capped at ${CAP_BYTES}.
${ELIDED} bytes elided between the head and tail shown here.
Full output: ${SPILL}
Read it with an offset/limit or grep it — do NOT re-run the command.
Command was: ${CMD}

"

printf '%s' "$HEAD_PART$NOTICE$TAIL_PART" | jq -Rs \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", updatedToolOutput: .}}'
exit 0
