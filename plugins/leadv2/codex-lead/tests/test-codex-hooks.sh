#!/bin/bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; HOOK="$ROOT/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh"; LIFE="$ROOT/marketplace/plugins/leadv2/hooks/leadv2-subagent-lifecycle.sh"; FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT; PASS=0; FAIL=0
pass(){ PASS=$((PASS+1)); printf '[PASS] %s\n' "$1"; }; fail(){ FAIL=$((FAIL+1)); printf '[FAIL] %s\n' "$1"; }
allow(){ local o r; o="$(printf '%s' "$2" | LEADV2_CODEX_LV2GUARD="$ROOT/lv2guard.sh" bash "$HOOK")"; r=$?; [[ $r -eq 0 && -z "$o" ]] && pass "$1" || fail "$1 rc=$r out=$o"; }
deny(){ local o r; o="$(printf '%s' "$2" | LEADV2_CODEX_LV2GUARD="$ROOT/lv2guard.sh" bash "$HOOK")"; r=$?; [[ $r -eq 0 && "$o" == *'"permissionDecision":"deny"'* ]] && pass "$1" || fail "$1 rc=$r out=$o"; }
ISOLATED="$FIX/.claude/worktrees/lane-1"; mkdir -p "$ISOLATED"
allow 'shell allow' '{"tool_name":"exec_command","tool_input":{"command":"git status"}}'
deny 'patch denies main cwd' "{\"tool_name\":\"apply_patch\",\"cwd\":\"$FIX\",\"tool_input\":{\"command\":\"*** Update File: a.txt\"}}"
allow 'patch allows isolated relative target' "{\"tool_name\":\"apply_patch\",\"cwd\":\"$ISOLATED\",\"tool_input\":{\"command\":\"*** Update File: a.txt\"}}"
deny 'patch denies absolute escape' "{\"tool_name\":\"apply_patch\",\"cwd\":\"$ISOLATED\",\"tool_input\":{\"command\":\"*** Update File: /tmp/x\"}}"
deny 'patch denies dotdot escape' "{\"tool_name\":\"apply_patch\",\"cwd\":\"$ISOLATED\",\"tool_input\":{\"command\":\"*** Update File: ../x\"}}"
allow 'exact MCP read allowlist' '{"tool_name":"mcp__codebase_memory_mcp__search_graph","tool_input":{"query":"find r m"}}'
deny 'MCP search and delete fails closed' '{"tool_name":"mcp__x__search_and_delete","tool_input":{}}'
export LEADV2_CODEX_READONLY_MCP_ALLOWLIST=mcp__private__read_thing; allow 'MCP environment extension' '{"tool_name":"mcp__private__read_thing","tool_input":{}}'; unset LEADV2_CODEX_READONLY_MCP_ALLOWLIST
for p in \
 '{"tool_name":"spawn_agent","tool_input":{"task_name":"triage","message":"read","fork_turns":"none"}}' \
 '{"tool_name":"followup_task","tool_input":{"target":"triage","message":"continue"}}' \
 '{"tool_name":"send_message","tool_input":{"target":"triage","message":"note"}}' \
 '{"tool_name":"wait_agent","tool_input":{"timeout_ms":10000}}' \
 '{"tool_name":"interrupt_agent","tool_input":{"target":"triage"}}' \
 '{"tool_name":"list_agents","tool_input":{}}' \
 '{"tool_name":"update_plan","tool_input":{"plan":[{"step":"review","status":"in_progress"}]}}'; do
  allow 'native continuation shape' "$p"
done
deny 'malformed payload' '{broken'
REG="$FIX/registry"; for n in $(seq 1 64); do printf '{"agent_id":"a-%s"}' "$n" | LEADV2_NATIVE_AGENT_REGISTRY="$REG" bash "$LIFE" start & done; wait
python3 - "$REG" <<'PY'
import json,pathlib,sys
files=list(pathlib.Path(sys.argv[1]).glob('*.json')); assert len(files)==64; assert {json.loads(p.read_text())['agent_id'] for p in files}=={'a-'+str(i) for i in range(1,65)}
PY
[[ $? -eq 0 ]] && pass '64 concurrent starts remain visible' || fail '64 concurrent starts'
for n in $(seq 1 32); do printf '{"agent_id":"a-%s"}' "$n" | LEADV2_NATIVE_AGENT_REGISTRY="$REG" bash "$LIFE" stop & done; wait
python3 - "$REG" <<'PY'
import json,pathlib,sys
ids={json.loads(p.read_text())['agent_id'] for p in pathlib.Path(sys.argv[1]).glob('*.json')}; assert ids=={'a-'+str(i) for i in range(33,65)}
PY
[[ $? -eq 0 ]] && pass 'concurrent stops remove only own entries' || fail 'concurrent stops'
printf '[SUMMARY] pass=%d fail=%d\n' "$PASS" "$FAIL"; [[ $FAIL -eq 0 ]]
