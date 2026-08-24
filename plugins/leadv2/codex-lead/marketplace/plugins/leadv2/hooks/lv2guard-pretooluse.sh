#!/bin/bash
# Typed Codex PreToolUse adapter: only a shell command is sent to lv2guard.
set -u
json_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"; printf '%s' "$s" | tr -d '\000-\037'; }
deny() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"lv2guard: %s"}}\n' "$(json_escape "$1")"; exit 0; }
INPUT="$(cat 2>/dev/null || true)"
CLASSIFIED="$(printf '%s' "$INPUT" | python3 -c '
import base64,json,os,re,sys
try: event=json.load(sys.stdin)
except Exception: print("DENY\tunreadable PreToolUse payload"); raise SystemExit
if not isinstance(event,dict) or not isinstance(event.get("tool_name"),str) or not isinstance(event.get("tool_input"),dict): print("DENY\ttool_name and tool_input object are required"); raise SystemExit
name,inp=event["tool_name"],event["tool_input"]
shell={"Bash","bash","Shell","shell","exec_command","functions.exec","functions.exec_command","unified_shell"}
native={"spawn_agent":("task_name","message"),"followup_task":("target","message"),"send_message":("target","message"),"wait_agent":("timeout_ms",),"interrupt_agent":("target",),"list_agents":(),"update_plan":("plan",)}
if name in shell:
 c=inp.get("command"); print("SHELL\t"+base64.b64encode(c.encode()).decode() if isinstance(c,str) and c else "DENY\tshell tool requires a non-empty tool_input.command")
elif name in {"apply_patch","functions.apply_patch"}:
 c,cwd=inp.get("command"),event.get("cwd")
 if not isinstance(c,str) or not isinstance(cwd,str): print("DENY\tapply_patch requires typed cwd and tool_input.command")
 elif not re.search(r"(?:^|/)\.claude/worktrees/[^/]+(?:/|$)",cwd): print("DENY\tapply_patch is allowed only in an isolated .claude/worktrees lane")
 else:
  targets=[m.group(1).strip() for m in re.finditer(r"^\*\*\* (?:Update|Add|Delete) File: (.+)$",c,re.M)]
  if not targets: print("DENY\tapply_patch command has no patch targets")
  elif any(os.path.isabs(t) or ".." in t.split("/") or os.path.commonpath([os.path.abspath(cwd),os.path.abspath(os.path.join(cwd,t))]) != os.path.abspath(cwd) for t in targets): print("DENY\tapply_patch target escapes its isolated worktree")
  else: print("ALLOW")
elif name.removeprefix("functions.") in native:
 key=name.removeprefix("functions."); required=native[key]
 valid=all(k in inp for k in required) and all(isinstance(inp[k],str) for k in required if k not in {"timeout_ms","plan"}) and (key != "wait_agent" or isinstance(inp.get("timeout_ms"),int)) and (key != "update_plan" or isinstance(inp.get("plan"),list))
 print("ALLOW" if valid else "DENY\tnative control operation has an invalid typed payload")
elif name.startswith("mcp__"):
 allowed={"mcp__codebase_memory_mcp__search_graph","mcp__codebase_memory_mcp__trace_path","mcp__codebase_memory_mcp__get_code_snippet","mcp__codebase_memory_mcp__query_graph","mcp__codebase_memory_mcp__get_architecture"}; allowed.update(x for x in os.environ.get("LEADV2_CODEX_READONLY_MCP_ALLOWLIST","").split(":") if x)
 print("ALLOW" if name in allowed else "DENY\tunknown or write-capable MCP tool shape is refused")
elif name in {"Read","Glob","Grep"}: print("ALLOW")
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
