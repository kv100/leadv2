#!/usr/bin/env bash
# run-all-triggers: leadv2-spawn-arbiter-gate leadv2-route-arbiter
# BUILTIN-AGENT-SPAWN-DEADLOCK-01 (2026-09-10). The arbiter must never decide
# an arm the built-in Agent tool cannot pronounce: the gate hands the arbiter
# the speakable model pool (declared ONCE in the gate, never a second yaml)
# and pins the spawn's own model, the arbiter ranks inside that pool, an
# emptied pool refuses loudly by name, and the gate consults ONCE itself so
# the FIRST spawn attempt can pass. Fixtures are the brief's acceptance
# pairs; section H is the brief-mandated mutation -- strip the speakable
# filter inside _pool_contains and an arm OUTSIDE the speakable pool answers
# again, turning H0 red (ARM-SELECTION-ADMISSION-BANDS-01, 2026-09-16: after
# recon eligibility grew to include glm-flash/luna, the arm that answers is
# glm-flash, not freepool -- H2/H3 assert the property and the named arm).
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
OKQ="$(quota 10 10 10)"
reset_journal(){ : > "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE"; }
gate(){ ROUTE_TEST_QUOTA="${1:-$OKQ}" bash "${2:-$HOOK}" <<<"$3"; }
verdict(){ gate "${1:-$OKQ}" "${3:-$HOOK}" "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])'; }
reason(){ gate "${1:-$OKQ}" "${3:-$HOOK}" "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecisionReason",""))'; }
ctx(){ gate "${1:-$OKQ}" "${3:-$HOOK}" "$2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("additionalContext",""))'; }
arb(){ ROUTE_TEST_QUOTA="${2:-$OKQ}" bash "${3:-$ARB}" worker "$1"; }
PAY_EH='{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"haiku"}}'

echo "== A: the reproducer -- Explore + decided model passes on attempt ONE, one call =="
reset_journal
v="$(verdict "$OKQ" "$PAY_EH")"
[[ "$v" == "allow" ]] && pass 'A1 Explore+haiku -> allow, first attempt, no prior record' || fail "A1 verdict=$v"
c="$(ctx "$OKQ" "$PAY_EH")"
[[ "$c" == *'arm=haiku'* && "$c" == *'kind=recon'* ]] && pass 'A2 allow context names the recorded decision' || fail "A2 ctx=$c"
# the ctx call must have reused the record (lookup hit), not consulted again:
# exactly ONE decision row proves the whole pass cost one arbiter call.
rows="$(wc -l < "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" | tr -d ' ')"
[[ "$rows" == "1" ]] && pass "A3 exactly one consult for the whole pass (journal rows=$rows)" || fail "A3 journal rows=$rows"
python3 - "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" <<'PY' && pass 'A4 record: arm=haiku model=haiku, freepool excluded not_in_pool' || fail 'A4 record shape wrong'
import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
r=[x for x in rows if x.get('subtype')=='Explore' and x.get('arm')!='refuse']
assert r and r[0]['arm']=='haiku' and r[0]['model']=='haiku', rows
assert r[0].get('arm_excluded',{}).get('freepool')=='not_in_pool', r[0].get('arm_excluded')
PY

echo "== B: paired negatives -- a model the arbiter did not decide keeps the SAME refusal =="
for m in freepool-default kimi-k2; do
  reset_journal
  v="$(verdict "$OKQ" "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"Explore\",\"model\":\"$m\"}}")"
  r="$(reason "$OKQ" "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"Explore\",\"model\":\"$m\"}}")"
  [[ "$v" == "deny" ]] && pass "B1 model=$m -> deny" || fail "B1 model=$m verdict=$v"
  [[ "$r" == *'no route-arbiter decision is on record'* ]] && pass "B2 model=$m keeps the case-1 refusal opening" || fail "B2 model=$m opening changed: $r"
done
reset_journal
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"freepool-default"}}')"
[[ "$r" == *'requested_arm_not_in_pool'* ]] && pass 'B3 freepool-default refused as not_in_pool (unspeakable -- the right reason, no name list)' || fail "B3 freepool reason: $r"
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"kimi-k2"}}')"
[[ "$r" == *'requested_model_unknown'* ]] && pass 'B4 kimi-k2 refused as requested_model_unknown' || fail "B4 kimi reason: $r"

echo "== C: frontmatter agent (model on the definition, none on the call) still passes =="
reset_journal
v="$(verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"my-auditor"}}')"
[[ "$v" == "allow" ]] && pass 'C1 model-less custom agent -> allow (record binds subtype only)' || fail "C1 verdict=$v"
# the pre-change path is untouched: an EXISTING record unlocks with ZERO consults.
reset_journal
arb '{"work_kind":"build","size":"standard","subtype":"PinnedSub","task":"pre-existing record"}' >/dev/null
before="$(wc -l < "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" | tr -d ' ')"
v="$(LEADV2_SPAWN_GATE_AUTO_CONSULT=0 verdict "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"PinnedSub"}}')"
after="$(wc -l < "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" | tr -d ' ')"
[[ "$v" == "allow" && "$before" == "$after" ]] && pass 'C2 pre-existing record -> allow, journal untouched (old path)' || fail "C2 v=$v rows $before->$after"

echo "== D: emptied speakable pool -> the refusal NAMES the emptiness, never a fallback model =="
out="$(arb '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"empty pool probe","speakable_models":["nonexistent-model"]}' 2>&1)" || true
[[ "$out" == *'reason=pool_empty_all_excluded'* ]] && pass 'D1 emptied pool -> arbiter refuses pool_empty_all_excluded' || fail "D1 out=$out"
# Recon membership grew by founder proposal arm-selection-proposal-2026-09-16.md
# §4.1 item 5 (ARM-SELECTION-ADMISSION-BANDS-01, 2026-09-16): flash and luna
# (codex/glm-flash) now sit in the recon pool alongside freepool/haiku, so an
# emptied pool excludes all four -- do not "fix" this back to the old pair.
[[ "$out" == *'arm_excluded=codex:not_in_pool,freepool:not_in_pool,glm-flash:not_in_pool,haiku:not_in_pool'* ]] && pass 'D2 refusal names every excluded arm and stage' || fail "D2 tokens missing: $out"
sed 's/^SPEAKABLE_MODELS=.*/SPEAKABLE_MODELS="nonexistent-model"/' "$HOOK" > "$TMP/hook.emptypool"
mkdir -p "$TMP/etree/hooks" "$TMP/etree/scripts/lib"
cp "$TMP/hook.emptypool" "$TMP/etree/hooks/leadv2-spawn-arbiter-gate.sh"
cp "$ARB" "$TMP/etree/scripts/lib/"
reset_journal
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore"}}' "$TMP/etree/hooks/leadv2-spawn-arbiter-gate.sh")"
[[ "$r" == *'pool_empty_all_excluded'* ]] && pass 'D3 gate with emptied pool -> deny names pool_empty_all_excluded (no model substituted)' || fail "D3 reason: $r"

echo "== E: arbiter garbage or missing -> named refusal, never a pass =="
mkdir -p "$TMP/gtree/hooks" "$TMP/gtree/scripts/lib"
cp "$HOOK" "$TMP/gtree/hooks/"
printf '#!/usr/bin/env bash\necho "total garbage rc=1"\nexit 1\n' > "$TMP/gtree/scripts/lib/leadv2-route-arbiter.sh"
reset_journal
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"haiku"}}' "$TMP/gtree/hooks/leadv2-spawn-arbiter-gate.sh")"
[[ "$r" == *'no decision line'* && "$r" == *'rc=1'* ]] && pass 'E1 garbage arbiter -> deny names "no decision line (rc=1)"' || fail "E1 reason: $r"
mkdir -p "$TMP/ntree/hooks"
cp "$HOOK" "$TMP/ntree/hooks/"
reset_journal
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"haiku"}}' "$TMP/ntree/hooks/leadv2-spawn-arbiter-gate.sh")"
[[ "$r" == *'re-install the leadv2 plugin'* ]] && pass 'E2 arbiter missing -> deny names the re-install way forward' || fail "E2 reason: $r"

echo "== F: auto-consult kill switch reverts to deny-without-consulting =="
reset_journal
v="$(LEADV2_SPAWN_GATE_AUTO_CONSULT=0 verdict "$OKQ" "$PAY_EH")"
[[ "$v" == "deny" ]] && pass 'F1 AUTO_CONSULT=0 -> deny without consulting' || fail "F1 verdict=$v"
[[ ! -s "$LEADV2_ROUTE_ARBITER_DECISIONS_FILE" ]] && pass 'F2 journal untouched (no consult happened)' || fail 'F2 journal written anyway'
r="$(LEADV2_SPAWN_GATE_AUTO_CONSULT=0 reason "$OKQ" "$PAY_EH")"
[[ "$r" == *'LEADV2_SPAWN_GATE_AUTO_CONSULT=0'* ]] && pass 'F3 refusal names the auto-consult switch' || fail "F3 reason: $r"

echo "== G: the kind=recon assumption is named and escapable =="
r="$(reason "$OKQ" '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"sonnet"}}')"
for tok in requested_arm_incapable 'kind=recon assumed' 'work_kind'; do
  [[ "$r" == *"$tok"* ]] && pass "G names $tok" || fail "G missing $tok: $r"
done

echo "== H0: arbiter ranks INSIDE the speakable pool (pure auction, no pin) =="
reset_journal
out="$(arb '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"auction inside pool","speakable_models":["sonnet","opus","haiku","fable"]}' 2>&1)" || true
[[ "$out" == 'arm=haiku '* ]] && pass 'H0 auction inside pool -> haiku (freepool excluded by speakability, not by name)' || fail "H0 out=$out"

echo "== H: MUTATION -- strip the speakable filter inside _pool_contains; the arbiter must answer freepool again (H0 red) =="
mkdir -p "$TMP/mtree/scripts/lib"
python3 - "$ARB" "$TMP/mtree/scripts/lib/leadv2-route-arbiter.sh" <<'PY' && pass 'H1 mutation applied (speakable pool branch removed from _pool_contains body)' || fail 'H1 mutation patch failed'
import sys
src,dst=sys.argv[1],sys.argv[2]
needle="    if speakable is not None:\n        return any(str(c.get('model') or '') in speakable and c.get('pool_default',True) is not False for c in _arm_cells.get(arm,[]))\n"
s=open(src).read()
assert s.count(needle)==1, 'mutation anchor not unique: %d' % s.count(needle)
open(dst,'w').write(s.replace(needle,''))
PY
out="$(arb '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"auction inside pool","speakable_models":["sonnet","opus","haiku","fable"]}' "$OKQ" "$TMP/mtree/scripts/lib/leadv2-route-arbiter.sh" 2>&1)" || true
arm_won="$(sed -n 's/^arm=\([^ ]*\).*/\1/p' <<<"$out")"
case "$arm_won" in
  sonnet|opus|haiku|fable) fail "H2 mutation did not reproduce the defect: winner '$arm_won' is still inside the speakable pool: $out" ;;
  *) pass "H2 mutation bites: winner '$arm_won' is outside the speakable pool {sonnet,opus,haiku,fable} (H0 would be red -- the filter is the operative part)" ;;
esac
# ARM-SELECTION-ADMISSION-BANDS-01 promoted glm-flash to band 4, so it now
# outbids freepool on recon cost (cheapest_capable) once the filter is
# stripped -- name the arm so a silent membership change still fails loudly
# instead of passing on a weakened "any arm outside the pool" predicate.
[[ "$arm_won" == "glm-flash" ]] && pass 'H3 winner is named: glm-flash (cheapest_capable), not a wildcard' || fail "H3 expected winner glm-flash, got '$arm_won': $out"

printf 'SUMMARY: pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
