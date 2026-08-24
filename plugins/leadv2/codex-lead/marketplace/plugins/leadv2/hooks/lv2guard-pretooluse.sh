#!/bin/bash
# Typed Codex PreToolUse adapter: prose query fields never become shell input.
set -u
json_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"; printf '%s' "$s" | tr -d '\000-\037'; }
deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"lv2guard: %s"}}\n' "$(json_escape "$1")"; exit 0; }
INPUT="$(cat 2>/dev/null || true)"
CLASSIFIED="$(printf '%s' "$INPUT" | python3 -c '
import base64,json,re,sys
try: event=json.load(sys.stdin)
except Exception: print("DENY\tunreadable PreToolUse payload"); raise SystemExit
if not isinstance(event,dict) or not isinstance(event.get("tool_name"),str) or not isinstance(event.get("tool_input"),dict): print("DENY\ttool_name and tool_input object are required"); raise SystemExit
name,inp=event["tool_name"],event["tool_input"]
if name in {"Bash","bash","Shell","shell","exec_command","functions.exec","functions.exec_command","unified_shell"}:
 c=inp.get("command"); print("SHELL\t"+base64.b64encode(c.encode()).decode() if isinstance(c,str) and c else "DENY\tshell tool requires a non-empty tool_input.command")
elif name in {"apply_patch","functions.apply_patch"}:
 print("DENY\tnative apply_patch is a write channel; use the external dispatcher worktree" if isinstance(inp.get("patch",inp.get("input")),str) else "DENY\tapply_patch payload is not a typed patch string")
elif name in {"Agent","spawn_agent","functions.spawn_agent"}:
 print("ALLOW" if isinstance(inp.get("message"),str) and isinstance(inp.get("task_name"),str) and inp.get("shared_writes") is False else "DENY\tagent spawn requires typed task_name, message, and shared_writes=false")
elif name.startswith("mcp__"):
 leaf=name.rsplit("__",1)[-1].lower(); print("ALLOW" if re.search(r"(^|_)(search|get|query|trace|list|read|fetch|architecture|status)(_|$)",leaf) else "DENY\tunknown or write-capable MCP tool shape is refused")
elif name in {"Read","Glob","Grep","wait_agent","send_message","list_agents","interrupt_agent"}: print("ALLOW")
else: print("DENY\tunknown tool shape is refused until classified as read-only")
' 2>/dev/null || printf 'DENY\tunable to classify typed payload')"
KIND="${CLASSIFIED%%$'\t'*}"; DATA="${CLASSIFIED#*$'\t'}"
case "$KIND" in ALLOW) exit 0;; DENY) deny "$DATA";; SHELL) ;; *) deny 'unable to classify typed payload';; esac
CMD="$(printf '%s' "$DATA" | base64 --decode 2>/dev/null || true)"; [[ -n "$CMD" ]] || deny 'shell command could not be decoded'
GUARD="${LEADV2_CODEX_LV2GUARD:-}"
if [[ -n "${LEADV2_CODEX_LV2GUARD:-}" && ! -f "$GUARD" ]]; then deny "LEADV2_CODEX_LV2GUARD=$GUARD does not exist"; fi
if [[ -z "$GUARD" && -f "$(dirname "$0")/../../../../lv2guard.sh" ]]; then GUARD="$(dirname "$0")/../../../../lv2guard.sh"; fi
[[ -f "$GUARD" ]] || deny 'lv2guard.sh not resolvable'
ERR="$(bash "$GUARD" --check -c "$CMD" 2>&1 >/dev/null)"; RC=$?
case "$RC" in 0) exit 0;; 97) deny "${ERR:0:1000}";; 2) deny 'guard usage error';; *) deny "guard exited rc=$RC; failing closed";; esac
