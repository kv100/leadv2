#!/usr/bin/env bash
# hooks/leadv2-supervisor-guard.sh — PreToolUse hard block on supervisor
# self-work (T-n, SUPERVISOR-AUDIT-01 mission-c, design-map row 9: "Supervisor
# does no work itself" is policy-only today, no technical gate).
#
# ACTIVE only for the exact claude session that owns a LIVE .supervise-active
# sentinel (same resolve+pid-scope primitive as
# leadv2-supervise-fanout-guard.sh: sentinel path via leadv2-state-path.sh,
# liveness via os.kill(pid,0), scoping via _lv2_durable_pid). Fanout children
# (LEADV2_ASYNC_QUESTIONS marker) and unrelated concurrent sessions on the
# same repo are never touched.
#
# SUBAGENT EXEMPTION (fix round 1, review-verdict BLOCKING #6): scoping
# solely by durable Claude pid also matches in-session Agent workers spawned
# under interactive-lanes mode (leadv2-supervise-fanout-guard.sh's default
# mode explicitly permits the supervising session to spawn ANY subagent_type
# in-session) — those workers' subsequent Edit/Write/Bash calls arrive on the
# SAME OS process tree as the root supervising session, so pid-matching
# alone can't tell "the lead typed this" from "a spawned developer subagent
# is doing its job". Same identity signal leadv2-loop-detect-hook.sh already
# uses: a top-level `agent_id` field, or a `transcript_path` containing
# "/subagents/" — either marks this call as belonging to a spawned worker's
# own turn, not the root session's hands. Enforcement is scoped to the root
# supervising agent only.
#
# BLOCKS (when active, root session only):
#   Edit/Write/NotebookEdit targeting *.py *.sh *.ts *.tsx *.sql, or any path
#   under a migrations/ directory.
#   Bash: git commit/push, sed -i on a code file, or `>>` appending to one.
# ALWAYS ALLOWED: *.md, *.yaml/*.yml, every other tool/extension, any
# subagent-identified call.
#
# JSON-AWARE, SINGLE PROCESS (fix round 1, MAJOR #7): parsing and the
# allow/deny decision happen in ONE python3 invocation reading the raw JSON
# directly — no newline-delimited field dump reparsed by `sed -n Np`. The
# prior two-step design serialized `command` as a plain line, so a multiline
# Bash command (e.g. `echo ok\ngit push`, or any script whose git/sed/append
# line isn't the first) left only its first line in the reparsed variable and
# silently bypassed every pattern below. The command text now never leaves
# the python process as a bash string.
#
# Kill-switch: LEADV2_SUPERVISOR_GUARD=0. Fail-safe: any internal error
# exits 0 (never bricks the session).
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO — continuing" >&2; exit 0' ERR

[[ "${LEADV2_SUPERVISOR_GUARD:-1}" == "0" ]] && exit 0
# Fanout children carry this marker — never gated, same convention as
# leadv2-supervise-fanout-guard.sh.
[[ -n "${LEADV2_ASYNC_QUESTIONS:-}" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0

# One JSON-aware process: parse tool_name/file_path/cwd/subagent-identity AND
# compute the file/command BLOCK-candidate decision here, entirely inside
# python's own `re`/json handling — the raw (possibly multiline) command
# string never crosses a bash variable boundary. Output is exactly 5 lines,
# none of which can themselves contain an embedded newline.
PARSED="$(python3 -c "
import sys, json, re

try:
    d = json.loads(sys.argv[1])
except Exception:
    print('')
    sys.exit(0)

tool = d.get('tool_name', '') or ''
inp = d.get('tool_input') or {}
file_path = inp.get('file_path') or inp.get('notebook_path') or ''
cmd = inp.get('command') or ''
cwd = d.get('cwd') or ''

# Subagent identity (fix #6): same signal leadv2-loop-detect-hook.sh uses —
# a top-level agent_id, or a transcript_path under .../subagents/.
agent_id = d.get('agent_id') or inp.get('agent_id') or ''
if not agent_id:
    tp = d.get('transcript_path', '') or ''
    if '/subagents/' in tp:
        agent_id = 'subagent'
is_subagent = '1' if agent_id.strip() else '0'

CODE_EXT = ('.py', '.sh', '.ts', '.tsx', '.sql')
ALLOW_EXT = ('.md', '.yaml', '.yml')

def is_blocked_file(path):
    if not path:
        return False
    low = path.lower()
    if low.endswith(ALLOW_EXT):
        return False
    if low.endswith(CODE_EXT):
        return True
    if '/migrations/' in low or low.startswith('migrations/'):
        return True
    return False

if tool in ('Edit', 'Write', 'NotebookEdit'):
    decision = 'BLOCK' if is_blocked_file(file_path) else 'ALLOW'
elif tool == 'Bash':
    decision = 'ALLOW'
    if cmd:
        if re.search(r'(^|[;&|\n]|\s)git\s+(commit|push)\b', cmd):
            decision = 'BLOCK'
        elif re.search(r'(^|[;&|\n]|\s)sed\s+-i\b', cmd) and re.search(r'\.(py|sh|ts|tsx|sql)\b', cmd):
            decision = 'BLOCK'
        elif re.search(r'>>\s*[^\s]*\.(py|sh|ts|tsx|sql)\b', cmd):
            decision = 'BLOCK'
else:
    decision = 'SKIP'  # not a gated tool at all

print(tool)
print(file_path)
print(cwd)
print(is_subagent)
print(decision)
" "$INPUT" 2>/dev/null || true)"
[[ -z "$PARSED" ]] && exit 0

TOOL_NAME="$(printf -- '%s' "$PARSED" | sed -n '1p')"
CWD_FROM_INPUT="$(printf -- '%s' "$PARSED" | sed -n '3p')"
[[ -z "$CWD_FROM_INPUT" ]] && CWD_FROM_INPUT="$PWD"
IS_SUBAGENT="$(printf -- '%s' "$PARSED" | sed -n '4p')"
CANDIDATE_DECISION="$(printf -- '%s' "$PARSED" | sed -n '5p')"
[[ -z "$TOOL_NAME" || "$CANDIDATE_DECISION" == "SKIP" ]] && exit 0

# Enforce self-work only for the root supervising agent — any call carrying
# subagent/agent identity is a spawned worker doing its job, never gated.
[[ "$IS_SUBAGENT" == "1" ]] && exit 0

# Resolve sentinel + registry (same fallback pattern as
# leadv2-supervise-fanout-guard.sh).
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh" ]]; then
  RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-state-path.sh"
  REGISTRY="${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-active-registry.sh"
else
  _LV2_D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  RESOLVER="${_LV2_D}/../scripts/leadv2-state-path.sh"
  REGISTRY="${_LV2_D}/../scripts/leadv2-active-registry.sh"
fi
[[ -x "$RESOLVER" ]] || exit 0

SENTINEL="$(PROJECT_ROOT="$CWD_FROM_INPUT" "$RESOLVER" --no-link .supervise-active 2>/dev/null || true)"
[[ -z "$SENTINEL" || ! -f "$SENTINEL" ]] && exit 0

SENTINEL_INFO="$(python3 -c "
import sys, json, os
path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as fh:
        d = json.load(fh) or {}
    pid = d.get('pid')
    if pid is None:
        print('DEAD'); print(''); sys.exit(0)
    try:
        os.kill(int(pid), 0)
        print('LIVE'); print(int(pid))
    except (TypeError, ValueError, ProcessLookupError, PermissionError):
        print('DEAD'); print('')
except Exception:
    print('DEAD'); print('')
" "$SENTINEL" 2>/dev/null || printf -- 'DEAD\n\n')"

SENTINEL_STATUS="$(printf -- '%s' "$SENTINEL_INFO" | sed -n '1p')"
SENTINEL_PID="$(printf -- '%s' "$SENTINEL_INFO" | sed -n '2p')"

if [[ "$SENTINEL_STATUS" != "LIVE" ]]; then
  # Stale sentinel (owning session already died) — self-clean and allow.
  rm -f "$SENTINEL" 2>/dev/null || true
  exit 0
fi

MY_PID=""
if [[ -f "$REGISTRY" ]]; then
  # shellcheck source=leadv2-active-registry.sh
  source "$REGISTRY"
  MY_PID="$(_lv2_durable_pid 2>/dev/null || true)"
fi
[[ -z "$MY_PID" || "$MY_PID" != "$SENTINEL_PID" ]] && exit 0

[[ "$CANDIDATE_DECISION" != "BLOCK" ]] && exit 0

python3 -c "
import json
print(json.dumps({'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':'deny','permissionDecisionReason':'Supervisor does not work by hand — dispatch it (leadv2-dispatch-code.sh). Override: export LEADV2_SUPERVISOR_GUARD=0'}}))
"
exit 2
