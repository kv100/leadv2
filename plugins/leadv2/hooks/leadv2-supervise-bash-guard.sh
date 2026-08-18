#!/usr/bin/env bash
# PreToolUse:Bash guard — a supervisor coordinates through approved leadv2
# control-plane commands; investigation belongs to a worker lane.
set -euo pipefail
trap 'echo "[$(basename "$0")] error at line $LINENO — continuing" >&2; exit 0' ERR

[[ "${LEADV2_SUPERVISE_GUARD:-1}" == "0" || "${LEADV2_SUPERVISE_BASH_GUARD:-1}" == "0" ]] && exit 0
[[ -n "${LEADV2_ASYNC_QUESTIONS:-}" ]] && exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -z "$INPUT" ]] && exit 0
PARSED="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d=json.load(sys.stdin); i=d.get("tool_input") or {}
    print((i.get("command") or "").strip())
    print((d.get("cwd") or "").strip())
except Exception: pass
' 2>/dev/null || true)"
COMMAND="$(printf '%s' "$PARSED" | sed -n '1p')"
CWD_FROM_INPUT="$(printf '%s' "$PARSED" | sed -n '2p')"
[[ -z "$COMMAND" ]] && exit 0
[[ -z "$CWD_FROM_INPUT" ]] && CWD_FROM_INPUT="$PWD"

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

SENTINEL_INFO="$(python3 -c '
import json, os, sys
try:
  with open(sys.argv[1], encoding="utf-8") as f: pid=(json.load(f) or {}).get("pid")
  os.kill(int(pid), 0); print("LIVE"); print(int(pid))
except Exception: print("DEAD"); print("")
' "$SENTINEL" 2>/dev/null || printf 'DEAD\n\n')"
SENTINEL_STATUS="$(printf '%s' "$SENTINEL_INFO" | sed -n '1p')"
SENTINEL_PID="$(printf '%s' "$SENTINEL_INFO" | sed -n '2p')"
if [[ "$SENTINEL_STATUS" != "LIVE" ]]; then rm -f "$SENTINEL" 2>/dev/null || true; exit 0; fi
MY_PID=""
if [[ -f "$REGISTRY" ]]; then source "$REGISTRY"; MY_PID="$(_lv2_durable_pid 2>/dev/null || true)"; fi
[[ -z "$MY_PID" || "$MY_PID" != "$SENTINEL_PID" ]] && exit 0

# Split command chains before validating.  A permitted command in one segment
# never authorizes ssh/git/etc. in a later segment.
if ! printf '%s' "$COMMAND" | python3 -c '
import os, re, shlex, sys
allowed = re.compile(r"^(leadv2-supervise(?:-[A-Za-z0-9_.]+)?\\.sh|leadv2-fanout\\.sh|leadv2-(?:ask|answer|state-path|active-registry|journal)\\.sh)$")
segments = [s.strip() for s in re.split(r";|&&|\\|\\||\\|", sys.stdin.read())]
for segment in segments:
    if not segment: continue
    try: words = shlex.split(segment)
    except ValueError: sys.exit(1)
    if words and words[0] == "env":
        words.pop(0)
        while words and (words[0].startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])): words.pop(0)
    while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]): words.pop(0)
    if not words: continue
    if words[0] == "cd" and len(words) >= 2: continue
    if not allowed.fullmatch(os.path.basename(words[0])): sys.exit(1)
'; then
  trap - ERR
  REASON='supervise mode: coordinators delegate, they don'"'"'t probe. Hand this to a worker — Agent(subagent_type=devops-engineer) for VPS/ops, Explore for read-only search, general-purpose otherwise. Allowed Bash here: leadv2-supervise*.sh, leadv2-fanout.sh, leadv2-ask/answer.sh, leadv2-state-path.sh. Override: export LEADV2_SUPERVISE_BASH_GUARD=0'
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}}))' "$REASON"
  printf '%s\n' "$REASON" >&2
  exit 2
fi
