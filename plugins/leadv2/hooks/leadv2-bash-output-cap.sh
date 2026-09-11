#!/usr/bin/env bash
# PostToolUse hook for Bash: warn when a command returns a lot of output without
# having truncated at source, so the NEXT call pipes through head/tail/grep -m.
#
# History, so nobody re-derives it (measured 2026-09-12, 2.1.269):
#
#  1. This hook read `.tool_output` and `.tool_response.output`. Neither key
#     exists. A captured live payload has
#     tool_response = {stdout, stderr, interrupted, isImage, noOutputExpected,
#                      backgroundTaskId, timedOutAfterMs, backgroundCwdHint}
#     so SIZE was always 1, the size guard always fired, and the hook did
#     nothing at all. Negative control: the old script emitted nothing on a
#     40,000-byte payload. It had been inert for its whole life.
#
#  2. Returning `hookSpecificOutput.updatedToolOutput` to REPLACE the oversized
#     result does not work here. Tried and falsified twice: the hook ran (proved
#     by spill files whose byte counts matched the outputs exactly, 28,771 and
#     30,074), emitted valid JSON, and the full output still arrived in the
#     transcript -- in this session and in a fresh headless one. So the
#     "turn this into a class-C rewriter for -9..12k/turn" lever is dead.
#     Do not spend another session on it without new evidence from the binary.
#
#  3. It is also not needed for the extreme case: Claude Code already persists a
#     very large Bash result itself and shows only a preview
#     ("Output too large (385.8KB). Full output saved to ...", first 2KB shown).
#     What is left for this hook is the middle band -- big enough to hurt when
#     re-read on every later turn, not big enough for the native cap.
#
# Hence: warn, with the key that actually works, and nothing more.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0
[[ "${LEADV2_BASH_OUTPUT_CAP:-1}" == "0" ]] && exit 0

WARN_BYTES="${LEADV2_BASH_OUTPUT_WARN_BYTES:-12000}"

OUT="$(printf '%s' "$INPUT" | jq -r '
  ((.tool_response.stdout? // "") + (.tool_response.stderr? // ""))
  | if type == "string" then . else tostring end' 2>/dev/null || true)"

SIZE=${#OUT}
[[ "$SIZE" -le "$WARN_BYTES" ]] && exit 0

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | head -c 200 || true)"

# Did the command already bound its output at source?
if printf '%s' "$CMD" | grep -qE '\| *(head|tail)|head -[0-9]+|tail -[0-9]+|grep -m ?[0-9]+|-c\b|wc -l|jq -r|--stat'; then
  exit 0
fi

KB=$((SIZE / 1024))
cat >&2 <<MSG
[leadv2-bash-output-cap] ${KB}KB from a command that did not bound its output.
  cmd: ${CMD:0:120}
  These bytes are in the transcript now and are re-sent on every later turn.
  Next time bound it at source: '| head -50', '| tail -30', 'grep -m 5', '--stat'.
MSG
exit 0
