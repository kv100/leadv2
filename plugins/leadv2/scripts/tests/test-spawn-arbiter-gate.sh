#!/usr/bin/env bash
# run-all-triggers: leadv2-spawn-arbiter-gate leadv2-route-arbiter
# ROUTING-EVERY-SPAWN-THROUGH-THE-ARBITER-01 (founder 2026-09-04).
# Part 1: the arbiter answers for work_kind build|recon|review|plan, decision
#         line names the kind, recon rows are config-driven (freepool healthy,
#         haiku fallback).
# Part 2: leadv2-spawn-arbiter-gate.sh denies any Agent spawn with no fresh
#         non-refused arbiter decision bound to its subagent_type (and model,
#         when pinned). Predicate is the ABSENCE of a record -- the suite must
#         catch any name list ever creeping in as much as any inert guard.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${SCRIPTS_DIR}/../hooks/leadv2-spawn-arbiter-gate.sh"
ARB="${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh"
ROUTING="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
export LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING"
export LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh"
export LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh"
export LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state"
export LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/decisions.jsonl"
: > "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE"
consult(){ ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" bash "$ARB" worker "$3"; }
gate(){ ROUTE_TEST_QUOTA="${1:-10,10,10}" LEADV2_ROUTE_DECISION_TTL="${LEADV2_ROUTE_DECISION_TTL_OVERRIDE:-900}" \
  ROUTE_TEST_FREE_RC="${ROUTE_TEST_FREE_RC_OVERRIDE:-0}" bash "$HOOK" <<<"$2"; }
verdict(){ gate "$1" "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])'; }
reason(){ gate "$1" "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecisionReason",""))'; }
ctx(){ gate "$1" "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("additionalContext",""))'; }
OKQ="$(quota 10 10 10)"

echo "== Part 1: four kinds =="
for k in build recon review plan; do
  out="$(consult "$OKQ" 0 "{\"work_kind\":\"$k\",\"size\":\"standard\",\"subtype\":\"Explore\",\"task\":\"p1-$k\"}")"
  if [[ "$out" == *"kind=$k "* && "$out" == *'arm=refuse '* ]]; then fail "p1 $k refused unexpectedly: $out"
  elif [[ "$out" == *"kind=$k "* ]]; then pass "p1 $k -> $(printf '%s' "$out" | grep -oE '^arm=[^ ]+')"; else fail "p1 $k line has no kind=$k: $out"; fi
done
out="$(consult "$OKQ" 0 '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"p1-recon-healthy"}')"
[[ "$out" == 'arm=freepool '* ]] && pass 'p1 recon healthy gate -> freepool (cheapest capable)' || fail "p1 recon healthy -> $out"
out="$(consult "$OKQ" 1 '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"p1-recon-benched"}')"
[[ "$out" == 'arm=haiku '* ]] && pass 'p1 recon benched freepool -> haiku fallback' || fail "p1 recon benched -> $out"

echo "== Part 2: six cases =="
: > "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE"
# (1) no decision -> deny, way forward + kill switch named.
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"sonnet"}}')"
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"sonnet"}}')"
[[ "$v" == "deny" ]] && pass 'case1 no decision -> deny' || fail "case1 verdict=$v"
for token in "leadv2-route-arbiter.sh" "leadv2-dispatch-code.sh" "LEADV2_ROUTE_ENFORCE=0"; do
  [[ "$r" == *"$token"* ]] && pass "case1 refusal names $token" || fail "case1 refusal missing $token: $r"
done
# (2) consult -> same spawn passes; decision readable back from the journal.
consult "$OKQ" 0 '{"work_kind":"build","size":"standard","subtype":"developer","task":"case2"}' >/dev/null
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"glm-5.3-flash"}}')"
c="$(ctx "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"glm-5.3-flash"}}')"
[[ "$v" == "allow" ]] && pass 'case2 consulted spawn -> allow' || fail "case2 verdict=$v"
[[ "$c" == *'arm=glm-flash'* && "$c" == *'kind=build'* ]] && pass 'case2 allow context names the recorded decision' || fail "case2 ctx=$c"
grep -q '"subtype": "developer"' "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" && pass 'case2 decision readable back from journal' || fail 'case2 journal read-back missing developer record'
# (3) general-purpose write-capable, no decision -> deny.
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose"}}')"
[[ "$v" == "deny" ]] && pass 'case3 general-purpose -> deny' || fail "case3 verdict=$v"
# (4) non-Claude arms without a decision -> deny (the door nobody names).
for m in kimi-k2 glm-5.3 freepool-default; do
  v="$(verdict "$OKQ" "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"developer\",\"model\":\"$m\"}}")"
  [[ "$v" == "deny" ]] && pass "case4 model=$m -> deny" || fail "case4 model=$m verdict=$v"
done
# (5) recon: consult -> cheap arm -> spawn proceeds (NOT denied).
consult "$OKQ" 0 '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"case5"}' >/dev/null
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore"}}')"
[[ "$v" == "allow" ]] && pass 'case5 recon consulted -> allow (Part 1 complete so enforcement may ship)' || fail "case5 verdict=$v"
# (6) kill switch -> everything passes.
v="$(LEADV2_ROUTE_ENFORCE=0 verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"opus"}}')"
[[ "$v" == "allow" ]] && pass 'case6 LEADV2_ROUTE_ENFORCE=0 -> allow without any decision' || fail "case6 verdict=$v"

echo "== hardening: the holes a name list would leave =="
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"sonnet"}}')"
[[ "$v" == "deny" ]] && pass 'model mismatch vs decided model -> deny (model_requested never matches)' || fail "mismatch verdict=$v"
# stale record is not a decision.
consult "$OKQ" 0 '{"work_kind":"recon","size":"standard","subtype":"StaleSub","task":"stale"}' >/dev/null
sleep 2
v="$(LEADV2_ROUTE_DECISION_TTL_OVERRIDE=1 verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"StaleSub"}}')"
[[ "$v" == "deny" ]] && pass 'expired record -> deny' || fail "stale verdict=$v"
# a refusal record must never unlock a spawn.
: > "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE"
consult "$(quota 99 99 99)" 1 '{"work_kind":"build","size":"standard","subtype":"RefusedSub","task":"refused"}' >/dev/null 2>&1 || true
grep -q '"arm": "refuse"' "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" && pass 'refusal recorded' || fail 'refusal not recorded'
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"RefusedSub"}}')"
[[ "$v" == "deny" ]] && pass 'refuse record does not unlock the spawn' || fail "refuse verdict=$v"
# NEGATIVE CONTROL: flip the emission site to allow and case 1 must PASS;
# restore and it must deny again. An inert guard is indistinguishable by silence.
sed 's/emit_decision "deny" "\$DENY"/emit_decision "allow" "$DENY"/' "$HOOK" > "$TMP/hook.negctl"
v="$(LEADV2_ROUTE_ARBITER_DECISIONS_FILE="$TMP/empty.jsonl" ROUTE_TEST_QUOTA="$OKQ" bash "$TMP/hook.negctl" <<< '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"sonnet"}}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])')"
[[ "$v" == "allow" ]] && pass 'NEGCTL flipped emission -> case1 passes (guard is the operative part)' || fail "negctl flipped verdict=$v"
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","model":"sonnet"}}')"
[[ "$v" == "deny" ]] && pass 'NEGCTL restored -> case1 denies again' || fail "negctl restored verdict=$v"

printf 'SUMMARY: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
