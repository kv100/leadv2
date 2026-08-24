#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; HOOK="$ROOT/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh"; LIFE="$ROOT/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh"; FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT; PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$1"; }; fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$1"; }
allow(){ local o r; o="$(printf '%s' "$2" | LEADV2_CODEX_LV2GUARD="$ROOT/lv2guard.sh" bash "$HOOK")"; r=$?; [[ $r -eq 0 && -z "$o" ]] && pass "$1" || fail "$1 rc=$r out=$o"; }
deny(){ local o r; o="$(printf '%s' "$2" | LEADV2_CODEX_LV2GUARD="$ROOT/lv2guard.sh" bash "$HOOK")"; r=$?; [[ $r -eq 0 && "$o" == *'"permissionDecision":"deny"'* ]] && pass "$1" || fail "$1 rc=$r out=$o"; }
allow 'shell allow' '{"tool_name":"exec_command","tool_input":{"command":"git status"}}'
BAD='r'"m -rf /"; deny 'shell deny' "{\"tool_name\":\"exec_command\",\"tool_input\":{\"command\":\"$BAD\"}}"
allow 'search text is not shell' "{\"tool_name\":\"mcp__codebase_memory_mcp__search_graph\",\"tool_input\":{\"query\":\"find $BAD examples\"}}"
deny 'apply_patch write' '{"tool_name":"apply_patch","tool_input":{"input":"*** Begin Patch"}}'; deny 'MCP write fails closed' '{"tool_name":"mcp__x__update_record","tool_input":{}}'
allow 'read-only agent' '{"tool_name":"spawn_agent","tool_input":{"task_name":"triage","message":"read","shared_writes":false,"fork_turns":"none"}}'; deny 'agent missing no-write' '{"tool_name":"spawn_agent","tool_input":{"task_name":"triage","message":"read"}}'; deny 'malformed payload' '{broken'
REG="$FIX/registry.json"; printf '%s' '{"agent_id":"a1","session_id":"s1","task_name":"triage"}' | LEADV2_NATIVE_AGENT_REGISTRY="$REG" bash "$LIFE" start
python3 - "$REG" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert 'a1' in d['agents']
PY
[[ $? -eq 0 ]] && pass 'lifecycle start' || fail 'lifecycle start'
printf '%s' '{"agent_id":"a1"}' | LEADV2_NATIVE_AGENT_REGISTRY="$REG" bash "$LIFE" stop
python3 - "$REG" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert not d['agents'] and d['last_event']['event']=='stop'
PY
[[ $? -eq 0 ]] && pass 'lifecycle stop' || fail 'lifecycle stop'
printf '[SUMMARY] pass=%d fail=%d\n' "$PASS" "$FAIL"; [[ $FAIL -eq 0 ]]
