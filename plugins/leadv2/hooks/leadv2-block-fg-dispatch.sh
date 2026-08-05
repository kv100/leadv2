#!/usr/bin/env bash
# PreToolUse:Bash — block foreground invocation of long-running leadv2 worker launchers.
# The Bash tool's 2-minute foreground timeout SIGTERMs the whole process group, killing
# a dispatch mid-flight with no diagnostic. This hook forces those launchers into the
# background (run_in_background / trailing & / nohup / setsid).
#
# Fail-open: empty stdin, parse failure, or any uncaught error → exit 0 (never wedge the lead).
# Override: append "# fg-dispatch: allow" to the command, or set LEADV2_ALLOW_FG_DISPATCH=1.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO" >&2; exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# Secondary escape hatch (mirrors LEADV2_ALLOW_FG in leadv2-block-fg-agent.sh).
[[ "${LEADV2_ALLOW_FG_DISPATCH:-0}" == "1" ]] && exit 0

# Single python3 pass: emit RIB on line 1, command on line 2+ (command may contain newlines).
# run_in_background normalised to: "true" / "false" / "" (key absent → tri-state).
_PARSE_OUT="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
    cmd = r.get("tool_input", {}).get("command", "")
    rib = r.get("tool_input", {}).get("run_in_background")
    rib_norm = "" if rib is None else ("true" if rib else "false")
    sys.stdout.write(rib_norm + "\n" + cmd)
except Exception:
    pass
' 2>/dev/null || true)"

# First line = RIB, rest = CMD (handles multi-line commands).
RIB="${_PARSE_OUT%%$'\n'*}"
if [[ "$RIB" == "$_PARSE_OUT" ]]; then
  CMD=""
else
  CMD="${_PARSE_OUT#*$'\n'}"
fi

# Both vars empty → parse failed → fail-open.
[[ -z "${CMD:-}" ]] && exit 0

# Override escape hatch.
printf '%s' "$CMD" | grep -q '# fg-dispatch: allow' && exit 0

# Target match: does the command mention a guarded launcher basename?
# Match on basename token so bash /abs/path/x.sh, ./x.sh, $DIR/x.sh, and bare alias all hit.
if ! printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_-])(leadv2-dispatch-code|leadv2-codex-session-runner|leadv2-fanout|glm-coder|omp-task)\.sh([^[:alnum:]_-]|$)'; then
  exit 0
fi

# Exemptions (any hit → allow).
# --no-spawn / LEADV2_DISPATCH_SPAWN=0: quick dry-run / no-launch mode.
printf '%s' "$CMD" | grep -Eq -- '--no-spawn|LEADV2_DISPATCH_SPAWN=0' && exit 0
# --help / -h.
printf '%s' "$CMD" | grep -Eq -- '--help|(^|[[:space:]])-h([[:space:]]|$)' && exit 0
# status / record-review subcommands (matched as whole words so path fragments don't match).
printf '%s' "$CMD" | grep -Eq '[[:space:]](status|record-review)([[:space:]]|$)' && exit 0

# Backgrounded test — allow if ANY of these are true:
# 1. run_in_background field is explicitly true (authoritative when present).
[[ "${RIB:-}" == "true" ]] && exit 0
# 2. Command ends with trailing & (whitespace before &, nothing but optional comment after).
printf '%s' "$CMD" | grep -Eq '[[:space:]]&[[:space:]]*(#.*)?$' && exit 0
# 3. nohup ... & present.
printf '%s' "$CMD" | grep -Eq 'nohup.*&' && exit 0
# 4. setsid present.
printf '%s' "$CMD" | grep -Eq 'setsid' && exit 0

# Deny.
cat >&2 <<MSG
[leadv2-block-fg-dispatch] BLOCKED
Foreground invocation of a leadv2 worker launcher — the 2-minute Bash tool timeout
would SIGTERM the process group and silently kill the dispatch mid-flight.
Run this instead:
  ${CMD} &
If you were only reading the file (grep/cat/echo), append:  # fg-dispatch: allow
Override: set LEADV2_ALLOW_FG_DISPATCH=1
MSG

exit 2
