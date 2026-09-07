#!/usr/bin/env bash
# Positive control + warn/enforce mode check for the direct-spawn gate
# (ROUTING-HAS-NO-ENFORCING-LAYER-01, warn-mode-default landing 2026-09-07).
set -uo pipefail

HOOK="/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-codex-first-nudge.sh"
SBX="$(mktemp -d)"
trap 'rm -rf "$SBX"' EXIT
REPO="$SBX/repo"
mkdir -p "$REPO/.claude" "$REPO/plugins/leadv2/config"
git -C "$REPO" init -q
cp /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/config/direct-spawn-gate.yaml "$REPO/plugins/leadv2/config/direct-spawn-gate.yaml"
JOURNAL="$SBX/journal.jsonl"
FAIL=0

payload() { # subagent_type prompt
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Agent','session_id':'s1','cwd':sys.argv[3],
  'tool_input':{'subagent_type':sys.argv[1],'prompt':sys.argv[2]}}))
" "$1" "$2" "$REPO"
}

run() { # [VAR=val ...]
  CLAUDE_PROJECT_ROOT="$REPO" CLAUDE_PLUGIN_ROOT="/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2" \
  LEADV2_DIRECT_SPAWN_GATE_JOURNAL="$JOURNAL" env "$@" bash "$HOOK" 2>"$SBX/err" >"$SBX/out"
}

ok() { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1"; FAIL=1; }

echo "== 1: default (no mode env) — write-capable, no reason, developer =="
run <<<"$(payload developer 'do a thing')"
RC=$?
if [[ $RC -eq 0 ]]; then ok "exits 0 (warn default never blocks)"; else bad "expected rc=0, got $RC ($(cat "$SBX/err"))"; fi
if grep -q '"decision": "deny"' "$JOURNAL" 2>/dev/null; then ok "journaled decision=deny (would-deny visible)"; else bad "expected a decision=deny journal line"; fi
: > "$JOURNAL"

echo "== 2: POSITIVE CONTROL — enforce mode (LEADV2_DIRECT_SPAWN_GATE_MODE=deny), same spawn =="
run LEADV2_DIRECT_SPAWN_GATE_MODE=deny <<<"$(payload developer 'do a thing')"
RC=$?
if [[ $RC -eq 2 ]]; then ok "exits 2 (gate actually enforces when flipped)"; else bad "expected rc=2, got $RC ($(cat "$SBX/err"))"; fi
grep -q "DENIED" "$SBX/err" && ok "stderr names DENIED" || bad "stderr missing DENIED: $(cat "$SBX/err")"
: > "$JOURNAL"

echo "== 3: sanctioned role (architect) — always passes, any mode =="
run LEADV2_DIRECT_SPAWN_GATE_MODE=deny <<<"$(payload architect 'design a thing')"
RC=$?
if [[ $RC -eq 0 ]]; then ok "sanctioned role exits 0 even in enforce mode"; else bad "expected rc=0, got $RC"; fi
grep -q '"decision": "sanctioned_bypass"' "$JOURNAL" 2>/dev/null && ok "journaled sanctioned_bypass" || bad "missing sanctioned_bypass journal line"
: > "$JOURNAL"

echo "== 4: recorded reason — passes, any mode =="
run LEADV2_DIRECT_SPAWN_GATE_MODE=deny <<<"$(payload developer $'do a thing\nLEADV2-DIRECT-REASON: hook surgery needs live lead context')"
RC=$?
if [[ $RC -eq 0 ]]; then ok "reasoned spawn exits 0 even in enforce mode"; else bad "expected rc=0, got $RC ($(cat "$SBX/err"))"; fi
grep -q '"decision": "allow_with_reason"' "$JOURNAL" 2>/dev/null && ok "journaled allow_with_reason" || bad "missing allow_with_reason journal line"
: > "$JOURNAL"

echo "== 5: kill switch LEADV2_DIRECT_SPAWN_GATE=0 — gate fully skipped, no journal at all =="
run LEADV2_DIRECT_SPAWN_GATE_MODE=deny LEADV2_DIRECT_SPAWN_GATE=0 <<<"$(payload developer 'do a thing')"
RC=$?
if [[ $RC -eq 0 ]]; then ok "kill switch: exits 0"; else bad "expected rc=0, got $RC"; fi
if [[ ! -s "$JOURNAL" ]]; then ok "kill switch: no journal entry written"; else bad "expected empty journal, got: $(cat "$JOURNAL")"; fi

if [[ "$FAIL" == "1" ]]; then echo "[GATE-WARNMODE] FAILED"; exit 1; fi
echo "[GATE-WARNMODE] All checks passed"
