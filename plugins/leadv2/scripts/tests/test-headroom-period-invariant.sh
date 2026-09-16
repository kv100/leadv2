#!/usr/bin/env bash
# changed-scope triggers, self-registered (scan_suite_triggers convention):
# run-all-triggers: leadv2-route-arbiter
# THE-BALANCER-CONCENTRATES-ON-THE-EMPTIEST-BUCKET-01 (founder, 2026-09-14):
# headroom_weight()'s rate-based ramp (_headroom_ramp on usable_now) was tuned
# against five_hour-scale rates and is nearly flat across the entire quota
# axis for any >=24h-period (weekly) window, so a provider at 83% used/36.8h
# to reset and a provider at 0% used/168h to reset differ by ~0.014 in
# headroom_weight -- a signal too weak to survive a normal cost/observed-cost
# term, concentrating picks on whichever weekly provider a coin-flip favours.
# This suite pins: (1) the fixed spread is wide, (2) paired resolves flip
# both ways, (3) the fix actually changes the OUTCOME under adversarial
# price noise (not just the raw number), (4) the five-hour window is
# admission-only -- its state never moves the headroom weight
# (WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01, founder order 2026-09-16,
# superseded the earlier "short-period windows ride the rate ramp unchanged"
# pin; cause class test_encodes_superseded_requirement), (5) a negative
# control proves the specific code is responsible.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
TMP="$(mktemp -d /private/tmp/test-headroom-period-invariant.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# Two weekly-bound arms, priced 1.0:1.0 by default so the paired-resolve
# fixture (a) isolates headroom_weight with no competing cost signal.
cat >"$TMP/routing-tied.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 95, review_pct: 95}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 95, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  cost: {glm: 1.0, codex: null, anthropic: null, freepool: 1.0}
  cost_unpriced_policy: matrix_median
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: codex, protected: true, sizes: [standard], kinds: [code]}
YML
# Same two arms, but codex priced 1.4x glm -- the adversarial fixture (c):
# a real, if crude, competing cost signal the headroom term must resist.
cat >"$TMP/routing-adversarial.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 95, review_pct: 95}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 95, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  cost: {glm: 1.0, codex: 1.4, anthropic: null, freepool: 1.0}
  cost_unpriced_policy: matrix_median
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: codex, protected: true, sizes: [standard], kinds: [code]}
YML
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
chmod +x "$TMP/free.sh" "$TMP/live.sh"

# quota <glm_weekly_pct> <glm_hours_to_reset> <codex_weekly_pct> <codex_hours_to_reset>
quota(){ python3 - "$@" <<'PY'
import json,sys
gp,gh,cp,ch=[float(x) for x in sys.argv[1:]]
def un(pct,hours): return max(0.0,100.0-pct)/max(hours,1.0)
print(json.dumps({
 'glm':{'status':'ok','five_hour':{'pct':10},
        'weekly':{'pct':gp,'hours_to_reset':gh,'usable_now':un(gp,gh)}},
 'codex':{'status':'ok','binding_window':'weekly','windows':[
   {'kind':'weekly','used_percent':cp,'hours_to_reset':ch,'usable_now':un(cp,ch)}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok',
   'five_hour':{'pct':10},'seven_day':{'pct':10}}]}
}))
PY
}
run(){
  local label="$1" routing="$2" q="$3" bin="${4:-$ARBITER}"
  env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$routing" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$label" \
    LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 \
    ROUTE_TEST_QUOTA="$q" \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$bin" '{"kind":"code","size":"standard","allowed_arms":["glm","codex"]}'
}
spread(){
  # extract the headroom_priced=codex:X,glm:Y token and print |X-Y|
  python3 - "$1" <<'PY'
import re,sys
m=re.search(r'headroom_priced=codex:([0-9.]+),glm:([0-9.]+)', sys.argv[1])
if not m: print('nan'); sys.exit(0)
print(abs(float(m.group(1))-float(m.group(2))))
PY
}

# (a) The founder-measured state (glm 83%/36.8h, codex 17%/100h, tied 1.0
# price) produces a WIDE headroom spread -- the true discriminating signal,
# not a ~0.014-wide sliver.
out_a="$(run founder "$TMP/routing-tied.yaml" "$(quota 83 36.8 17 100)")"
sp_a="$(spread "$out_a")"
if [[ "$out_a" == arm=codex\ * ]] && python3 -c "import sys; sys.exit(0 if float('$sp_a')>=0.3 else 1)"; then
  pass "(a) founder state: codex wins on a wide headroom spread (spread=$sp_a)"
else
  fail "(a) founder state did not produce a wide spread: spread=$sp_a out=$out_a"
fi

# (b) PAIRED RESOLVE, flips both ways: with the founder state flipped
# (glm healthy, codex now the near-exhausted one), the pick must MOVE to glm.
out_b="$(run flipped "$TMP/routing-tied.yaml" "$(quota 17 100 83 36.8)")"
if [[ "$out_b" == arm=glm\ * ]]; then
  pass '(b) flipped quota state: pick moves to glm (spread behaviour, not a fixed preference)'
else
  fail "(b) flipped state did not move the pick to glm: $out_b"
fi

# (c) ADVERSARIAL: add a real competing cost term (codex priced 1.4x glm) on
# top of the founder state. A signal wide enough to matter must survive it --
# codex (17% used, 100h to reset) is still the objectively healthier bucket
# and must still win despite costing more.
out_c="$(run adversarial "$TMP/routing-adversarial.yaml" "$(quota 83 36.8 17 100)")"
if [[ "$out_c" == arm=codex\ * ]]; then
  pass '(c) adversarial price noise (codex 1.4x): headroom spread still wins the healthier bucket'
else
  fail "(c) adversarial price noise flipped the pick to the WRONG (near-exhausted) arm: $out_c"
fi

# (d) WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01 (founder order 2026-09-16).
# Cause class test_encodes_superseded_requirement: until 2026-09-16 this case
# pinned "five_hour-scale window still rides the original rate ramp,
# unchanged (weight=0.6)" -- a five-hour rate as a PREFERENCE. Under the
# order the five-hour window is admission-only, so its state must not move
# the headroom weight at all. glm is priced from weekly 10pct used
# (0.2 + 0.8*0.9 = 0.92) with (i) a BURNT five_hour (80pct used, 5h) and
# (ii) a FRESH five_hour (10pct used, 5h): both runs must carry the SAME
# glm:0.92 token. On the pre-order code (i) priced ramp((100-80)/5=4)=0.6.
cat >"$TMP/routing-five.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 95, review_pct: 95}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 95, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  cost: {glm: 1.0, codex: null, anthropic: null, freepool: 1.0}
  cost_unpriced_policy: matrix_median
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: codex, protected: true, sizes: [standard], kinds: [code]}
YML
five_quota(){ python3 - "$@" <<'PY'
import json,sys
gp,gh=[float(x) for x in sys.argv[1:3]]
def un(pct,hours): return max(0.0,100.0-pct)/max(hours,1.0)
print(json.dumps({
 'glm':{'status':'ok','five_hour':{'pct':gp,'hours_to_reset':gh,'usable_now':un(gp,gh)},
        'weekly':{'pct':10,'hours_to_reset':100}},
 'codex':{'status':'ok','binding_window':'weekly','windows':[
   {'kind':'weekly','used_percent':10,'hours_to_reset':100,'usable_now':un(10,100)}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok',
   'five_hour':{'pct':10},'seven_day':{'pct':10}}]}
}))
PY
}
# Burnt five_hour (80pct used) vs fresh (10pct used): identical weekly-priced
# weight in both runs -- the five-hour state cannot move it.
out_d1="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing-five.yaml" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-five-burnt" LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 ROUTE_TEST_QUOTA="$(five_quota 80 5)" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" '{"kind":"code","size":"standard","allowed_arms":["glm","codex"]}')"
out_d2="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing-five.yaml" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-five-fresh" LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 ROUTE_TEST_QUOTA="$(five_quota 10 5)" bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" '{"kind":"code","size":"standard","allowed_arms":["glm","codex"]}')"
if [[ "$out_d1" == *'glm:0.92'* && "$out_d2" == *'glm:0.92'* ]]; then
  pass '(d) five-hour window is admission-only: burnt (80pct) and fresh (10pct) five_hour both price glm:0.92 from weekly alone'
else
  fail "(d) five-hour state moved the weekly-priced weight: burnt=$out_d1 fresh=$out_d2"
fi

# (e) NEGATIVE CONTROL: neutralise the weekly-reserve branch on a private
# copy (a constant weight for every arm). The founder case (a) must go RED
# (the spread collapses to 0 and loses the wide-spread assertion); the
# unmodified binary must then be GREEN again.
mut="$TMP/arbiter-without-period-invariant.sh"
python3 - "$ARBITER" "$mut" <<'PY'
import sys
s=open(sys.argv[1]).read()
old="""    _remaining_fraction=max(0.0,min(1.0,(100.0-float(_lp[1]))/100.0))
    _w=_HEADROOM_W_MIN+(_HEADROOM_W_MAX-_HEADROOM_W_MIN)*_remaining_fraction"""
if s.count(old)!=1: raise SystemExit('period-invariant anchor count=%d' % s.count(old))
open(sys.argv[2],'w').write(s.replace(old, '    _w=0.5'))
PY
if [[ -f "$mut" ]]; then
  out_e="$(run mut-founder "$TMP/routing-tied.yaml" "$(quota 83 36.8 17 100)" "$mut")"
  sp_e="$(spread "$out_e")"
  if python3 -c "import sys; sys.exit(0 if float('$sp_e')<0.1 else 1)"; then
    pass "(e RED) removing the period-invariant branch collapses the spread again (spread=$sp_e)"
  else
    fail "(e RED) mutation did not collapse the spread: spread=$sp_e out=$out_e"
  fi
else
  fail '(e) mutation copy was not created'
fi
out_e2="$(run mut-revert "$TMP/routing-tied.yaml" "$(quota 83 36.8 17 100)")"
sp_e2="$(spread "$out_e2")"
if [[ "$out_e2" == arm=codex\ * ]] && python3 -c "import sys; sys.exit(0 if float('$sp_e2')>=0.3 else 1)"; then
  pass "(e GREEN) unmutated arbiter restores the wide spread (spread=$sp_e2)"
else
  fail "(e GREEN) reverting mutation did not restore the wide spread: spread=$sp_e2 out=$out_e2"
fi

printf 'SUMMARY: pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
