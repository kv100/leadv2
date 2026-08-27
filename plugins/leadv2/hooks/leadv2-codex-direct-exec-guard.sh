#!/usr/bin/env bash
# hooks/leadv2-codex-direct-exec-guard.sh — PreToolUse:Bash
#
# Blocks a lead session from running a bare `codex exec` (which defaults to
# reasoning effort XHIGH and bypasses the router's quota gate). Routes to
# codex-task.sh / the leadv2 dispatch ladder instead.
#
# Allowlist (checked FIRST, before the deny rule):
#   - command invokes a sanctioned launcher:
#     codex-task.sh, leadv2-codex-session-runner.sh,
#     leadv2-codex-planner.sh, leadv2-codex-lead.sh
#   - LEADV2_ALLOW_DIRECT_CODEX=1 env (escape hatch, logged to stderr)
#
# Fail-open on any internal error (trap ERR → exit 0). Never blocks non-codex
# Bash, empty/malformed stdin, or non-Bash tools.
set -u
trap 'exit 0' ERR

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

CMD="$(printf '%s' "$INPUT" | python3 -c '
import sys, json
try:
    r = json.loads(sys.stdin.read())
    print(r.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null || true)"

[[ -n "$CMD" ]] || exit 0

# Allow sanctioned launchers (matched before the deny rule).
case "$CMD" in
  *codex-task.sh*|*leadv2-codex-session-runner.sh*|*leadv2-codex-planner.sh*|*leadv2-codex-lead.sh*)
    exit 0 ;;
esac

# Escape hatch (human-set in the invoking shell).
if [[ "${LEADV2_ALLOW_DIRECT_CODEX:-}" == "1" ]]; then
  printf '[leadv2-codex-direct-exec] ALLOWED direct codex exec (LEADV2_ALLOW_DIRECT_CODEX=1)\n' >&2
  exit 0
fi

# Escape hatch, inline env-prefix form (T16 §1, LEAD-FINAL-FIXES-01): the
# Bash tool runs each command in a fresh shell, so the documented override
# can only reach the command itself as a prefix assignment on the denied
# command. The hook's own process environment never sees that variable, so
# the check above missed it and the deny rule below blocked the one
# sanctioned override shape. A prefix assignment only takes effect for the
# command word it directly precedes, so it must sit in the SAME command
# segment (split on ; && || newline) immediately before the denied command
# word — an assignment appearing as an argument to another command
# (echo FOO=1; <denied>) must NOT unlock anything.
# c[o]dex/e[x]ec avoids this guard's literal-command self-scan matching its own regex.
if printf '%s' "$CMD" | tr '\n' ';' | sed -E 's/&&/;/g; s/\|\|/;/g' \
  | grep -qE '(^|;)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=([^[:space:];]+|"[^"]*")[[:space:]]+)*LEADV2_ALLOW_DIRECT_CODEX=1[[:space:]]+c[o]dex[[:space:]]+e[x]ec([[:space:]]|;|$)'; then
  printf '[leadv2-codex-direct-exec] ALLOWED direct run (inline LEADV2_ALLOW_DIRECT_CODEX=1 prefix)\n' >&2
  exit 0
fi

# Deny: `codex exec` as a standalone command word (not a subshell arg to a
# sanctioned launcher — those were already allowlisted above).
if printf '%s' "$CMD" | grep -qE '(^|[^A-Za-z0-9_/.-])codex[[:space:]]+exec([[:space:]]|$)'; then
  printf '[leadv2-codex-direct-exec] BLOCKED direct '\''codex exec'\'' — route via codex-task.sh --tier standard (effort+quota-gated). Override: LEADV2_ALLOW_DIRECT_CODEX=1\n' >&2
  exit 2
fi

exit 0
