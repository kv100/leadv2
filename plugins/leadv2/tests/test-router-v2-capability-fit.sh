#!/usr/bin/env bash
# ARBITER-SCORING-DESIGN-01 step 1. Covers docs/handoff/F1-ARBITER-SCORING-20260907/
# design.md §9.2's differ/match table (one case per row, ~8-9 rows) plus §9.3-style
# negative controls that prove a mutated capability tier or confidence default
# actually executes -- printing the literal changed token, not just a pass/fail.
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${ROOT}/scripts/lib/leadv2-route-arbiter.sh"
ROUTING="${ROOT}/config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
LAST_ASSERT="(none yet -- died before the first assertion)"
SUMMARY_PRINTED=0
_suite_abort_report() {
  local rc=$?
  [[ ${SUMMARY_PRINTED} -eq 1 ]] && return 0
  printf 'ABORT: suite exited rc=%s WITHOUT a summary after %s assertion(s); last completed: %s\n' \
    "${rc}" "$((PASS+FAIL))" "${LAST_ASSERT}" >&2
}
trap _suite_abort_report EXIT
pass(){ LAST_ASSERT="$1"; printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ LAST_ASSERT="$1"; printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit "${ROUTE_TEST_FREE_RC:-0}"
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

# All quota below is healthy (low used%) -- these tests assert WHICH capable arm
# wins on capability fit, not quota-driven refusal/demotion (that's test-route-
# arbiter.sh's job).
quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
HEALTHY="$(quota 10 20 20)"

run(){ # <routing-yaml> <descriptor-json> [extra-env...]
  local routing="$1" descriptor="$2"
  rm -f "$TMP/state"
  LEADV2_ROUTE_ARBITER_ROUTING_YAML="$routing" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  ROUTE_TEST_QUOTA="$HEALTHY" ROUTE_TEST_FREE_RC=0 \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$descriptor"
}
tok(){ printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed 's/.*=//'; }

# Custom matrix with NO glm cell, kind=code -- "glm capped" scenarios (§9.2 rows
# with codex/vol as the cheapest cost-pick).
cat >"$TMP/no-glm-code.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  capability_fit: {enabled: false, prior: 3.0, slack: 0.5, cap_default: 3.0, complexity_ordinal: {trivial: 1, simple: 2, standard: 3, complex: 4}, source_confidence: {judge: 0.9, flag: 0.7, heuristic: 0.4, unknown: 0.0}}
  capability_matrix:
    - {arm: codex, provider: codex, model: gpt-6-astra, tier: volume, cost: 3, protected: true, sizes: [standard], kinds: [code], capability: 3}
    - {arm: codex, provider: codex, model: gpt-6-astra, tier: standard, cost: 4, protected: true, sizes: [standard], kinds: [code], capability: 4}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, cost: 5, protected: true, sizes: [standard], kinds: [code], capability: 4}
YML

# Custom matrix with NO glm cell, kind=plan -- the haiku/codex/sonnet chain.
cat >"$TMP/no-glm-plan.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  capability_fit: {enabled: false, prior: 3.0, slack: 0.5, cap_default: 3.0, complexity_ordinal: {trivial: 1, simple: 2, standard: 3, complex: 4}, source_confidence: {judge: 0.9, flag: 0.7, heuristic: 0.4, unknown: 0.0}}
  capability_matrix:
    - {arm: haiku, provider: claude, model: haiku, tier: standard, cost: 2, protected: true, sizes: [standard], kinds: [plan], capability: 2}
    - {arm: codex, provider: codex, model: gpt-6-astra, tier: volume, cost: 3, protected: true, sizes: [standard], kinds: [plan], capability: 3}
    - {arm: codex, provider: codex, model: gpt-6-astra, tier: standard, cost: 4, protected: true, sizes: [standard], kinds: [plan], capability: 4}
    - {arm: sonnet, provider: claude, model: sonnet, tier: standard, cost: 5, protected: true, sizes: [standard], kinds: [plan], capability: 4}
YML

# ── §9.2 row 1: heuristic, simple, glm-flash cost-pick -> glm, differs=1 ────────
out="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"simple","complexity_source":"heuristic","task":"r1"}')"
exp_arm=glm; [[ "$(tok "$out" fit_mode)" != "on" ]] && exp_arm=glm-flash
if [[ "$(tok "$out" fit_pick)" == "glm" && "$(tok "$out" fit_differs)" == "1" && "$(tok "$out" arm)" == "$exp_arm" ]]; then
  pass '9.2 row1: heuristic/simple demotes glm-flash, fit_pick=glm fit_differs=1 (arm follows configured fit_mode)'
else
  fail "9.2 row1 out=$out"
fi

# ── §9.2 row 2: any(judge)/standard, glm-flash cost-pick -> glm, differs=1 ──────
out="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"r2"}')"
exp_arm=glm; [[ "$(tok "$out" fit_mode)" != "on" ]] && exp_arm=glm-flash
if [[ "$(tok "$out" fit_pick)" == "glm" && "$(tok "$out" fit_differs)" == "1" && "$(tok "$out" arm)" == "$exp_arm" ]]; then
  pass '9.2 row2: standard complexity (req_eff=3.0) demotes glm-flash, fit_pick=glm fit_differs=1'
else
  fail "9.2 row2 out=$out"
fi

# ── §9.2 row 3: unknown source, trivial complexity -> cautious req_eff=PRIOR, glm wins ──
out="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"trivial","complexity_source":"unknown","task":"r3"}')"
if [[ "$(tok "$out" fit_pick)" == "glm" && "$(tok "$out" fit_differs)" == "1" && "$(tok "$out" req_eff)" == "3.0" ]]; then
  pass '9.2 row3: unknown provenance is cautious (req_eff=3.0 regardless of low complexity), fit_pick=glm fit_differs=1'
else
  fail "9.2 row3 out=$out"
fi

# ── §9.2 row 4: complex, codex/vol cost-pick, glm capped -> codex/std, differs=1 ──
out="$(run "$TMP/no-glm-code.yaml" '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"r4"}')"
# fit_pick=/fit_differs= only ever name the arm (never the tier -- design.md
# §6 line 253's literal print format), so the live pick's own tier=volume
# proves enabled:false left it alone, and fit_bucket=codex:1,codex:0,sonnet:0
# (yaml declaration order: volume, standard, sonnet) proves the fit-favored
# candidate is codex's SECOND cell (standard, bucket0), not its first (volume,
# bucket1) -- the (arm,tier) identity fix, not the arm-only literal, is what
# makes fit_differs=1 here.
if [[ "$(tok "$out" fit_pick)" == "codex" && "$(tok "$out" fit_differs)" == "1" \
   && "$out" == *'tier=volume'* && "$out" == *'fit_bucket=codex:1,codex:0,sonnet:0'* ]]; then
  pass '9.2 row4: complex work with glm capped demotes codex/volume (cap3 short by1), fit_pick=codex(standard, per fit_bucket=codex:1,codex:0,...) fit_differs=1'
else
  fail "9.2 row4 out=$out"
fi

# ── §9.2 row 5: standard/complex, haiku cost-pick (kind=plan), glm capped -> codex/vol, differs=1 ──
out="$(run "$TMP/no-glm-plan.yaml" '{"kind":"plan","size":"standard","complexity":"standard","complexity_source":"judge","task":"r5"}')"
# Both codex cells land in bucket0 here (cap3 and cap4 both clear req_eff=3.0),
# so cost breaks the tie toward the cheaper volume cell -- fit_bucket=
# haiku:1,codex:0,codex:0,sonnet:0 confirms haiku alone is demoted, and design
# accepts either codex tier ("codex/vol or codex/std") for this row.
if [[ "$(tok "$out" fit_pick)" == "codex" && "$(tok "$out" fit_differs)" == "1" \
   && "$out" == *'arm=haiku '* && "$out" == *'fit_bucket=haiku:1,codex:0,codex:0,sonnet:0'* ]]; then
  pass '9.2 row5: plan work with glm capped demotes haiku (cap2), fit_pick=codex(volume, tie broken by cost) fit_differs=1'
else
  fail "9.2 row5 out=$out"
fi

# ── §9.2 row 6: any, glm cost-pick (size=heavy) -> glm, differs=0 (cap4 never demoted) ──
out="$(run "$ROUTING" '{"kind":"code","size":"heavy","complexity":"complex","complexity_source":"heuristic","task":"r6"}')"
if [[ "$(tok "$out" fit_pick)" == "glm" && "$(tok "$out" fit_differs)" == "0" && "$out" == *'arm=glm '* ]]; then
  pass '9.2 row6: glm (cap4) is cheapest and never demoted, fit_pick=glm fit_differs=0'
else
  fail "9.2 row6 out=$out"
fi

# ── §9.2 row 7: simple, sonnet cost-pick via allowed_arms restriction -> sonnet, differs=0 ──
out="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"simple","complexity_source":"heuristic","allowed_arms":["sonnet"],"task":"r7"}')"
if [[ "$(tok "$out" fit_pick)" == "sonnet" && "$(tok "$out" fit_differs)" == "0" && "$out" == *'arm=sonnet '* ]]; then
  pass '9.2 row7: allowed_arms filter precedes the fit sort, fit_pick=sonnet fit_differs=0'
else
  fail "9.2 row7 out=$out"
fi

# ── §9.2 row 8: Heavy task_class (Scenario D) -> glm, differs=0 ────────────────
out="$(run "$ROUTING" '{"kind":"code","task_class":"Heavy","complexity":"complex","complexity_source":"flag","task":"r8"}')"
if [[ "$(tok "$out" fit_pick)" == "glm" && "$(tok "$out" fit_differs)" == "0" && "$out" == *'arm=glm '* ]]; then
  pass '9.2 row8: --task-class Heavy (Scenario D) still resolves to glm via the capability table, fit_differs=0'
else
  fail "9.2 row8 out=$out"
fi

# ── §9.2 row 9: judge/flag, trivial/simple, glm-flash fits -> glm-flash, differs=0 ──
out="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"trivial","complexity_source":"judge","task":"r9"}')"
if [[ "$(tok "$out" fit_pick)" == "glm-flash" && "$(tok "$out" fit_differs)" == "0" && "$out" == *'arm=glm-flash '* ]]; then
  pass '9.2 row9: judge-trivial fits glm-flash (cap2), fit_pick=glm-flash fit_differs=0'
else
  fail "9.2 row9 out=$out"
fi

# ── negative control (a): a mutated capability tier must actually change fit_bucket ──
# routing.yaml: glm-flash capability 2 -> 4. Same descriptor as row2 (judge/standard);
# unmutated must show fit_bucket=glm-flash:1 (short by one step), mutated must show
# fit_bucket=glm-flash:0 (now cap4, fits) -- both read straight off the decision line.
python3 - "$ROUTING" "$TMP/mutated-cap.yaml" <<'PY'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
data = yaml.safe_load(open(src))
cells = data['router_v2']['capability_matrix']
flash = [c for c in cells if c.get('arm') == 'glm-flash']
if len(flash) != 1 or flash[0].get('capability') != 2:
    sys.exit('FIXTURE PRECONDITION GONE: glm-flash capability is not 2 in leadv2-routing.yaml -- re-anchor this control, do not silence it')
flash[0]['capability'] = 4
yaml.safe_dump(data, open(dst, 'w'))
PY
base="$(run "$ROUTING" '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"nc-a-base"}')"
mut="$(run "$TMP/mutated-cap.yaml" '{"kind":"code","size":"standard","complexity":"standard","complexity_source":"judge","task":"nc-a-mut"}')"
if [[ "$base" == *'fit_bucket='*'glm-flash:1'* && "$mut" == *'fit_bucket='*'glm-flash:0'* ]]; then
  pass 'NC(a): mutating glm-flash capability 2->4 flips its printed fit_bucket token from :1 to :0'
else
  fail "NC(a) base=$base mut=$mut"
fi

# ── negative control (b): req_eff=cx -> req_eff=PRIOR mutation must flip the winner ──
# Anchor is the cx>=PRIOR branch specifically (spacing distinguishes it from the
# cx-is-None branch's `req_eff=PRIOR`, which must NOT be touched).
MUT_B="$TMP/arbiter-nc-b.sh"; cp "$ARBITER" "$MUT_B"
python3 - "$MUT_B" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "elif cx >= PRIOR:         req_eff=cx"
n = s.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected 1) -- req_eff branch moved or was reworded; re-anchor this control, do not silence it' % n)
open(p, 'w').write(s.replace(anchor, "elif cx >= PRIOR:         req_eff=PRIOR"))
PY
base="$(LEADV2_ARBITER_CAPABILITY_FIT=on ARBITER="$ARBITER" run "$TMP/no-glm-code.yaml" '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"nc-b-base"}')"
ARBITER_SAVE="$ARBITER"; ARBITER="$MUT_B"
mut="$(LEADV2_ARBITER_CAPABILITY_FIT=on ARBITER="$MUT_B" run "$TMP/no-glm-code.yaml" '{"kind":"code","size":"standard","complexity":"complex","complexity_source":"judge","task":"nc-b-mut"}')"
ARBITER="$ARBITER_SAVE"
if [[ "$(tok "$base" req_eff)" == "4.0" && "$(tok "$base" tier)" == "standard" \
   && "$(tok "$mut" req_eff)" == "3.0" && "$(tok "$mut" tier)" == "volume" ]]; then
  pass 'NC(b): stripping confidence-discount on a >=PRIOR estimate flips req_eff=4.0->3.0 and the actual winner tier=standard->volume (FIT_MODE=on)'
else
  fail "NC(b) base=$base mut=$mut"
fi

# ── negative control (c): SRC_CONF default 0.0 -> 0.9 must flip conf/req_eff and,
# under FIT_MODE=on, the actual pick (design.md §9.3 row 3, reused verbatim). An
# off-vocabulary complexity_source ("banana") is required so the lookup actually
# falls through to the .get() default rather than an explicit yaml key.
MUT_C="$TMP/arbiter-nc-c.sh"; cp "$ARBITER" "$MUT_C"
python3 - "$MUT_C" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "SRC_CONF.get(complexity_source, 0.0)"
n = s.count(anchor)
if n != 1:
    sys.exit('mutation anchor found %d times (expected 1) -- SRC_CONF lookup moved or was reworded; re-anchor this control, do not silence it' % n)
open(p, 'w').write(s.replace(anchor, "SRC_CONF.get(complexity_source, 0.9)"))
PY
base="$(LEADV2_ARBITER_CAPABILITY_FIT=on ARBITER="$ARBITER" run "$ROUTING" '{"kind":"code","size":"standard","complexity":"simple","complexity_source":"banana","task":"nc-c-base"}')"
mut="$(LEADV2_ARBITER_CAPABILITY_FIT=on ARBITER="$MUT_C" run "$ROUTING" '{"kind":"code","size":"standard","complexity":"simple","complexity_source":"banana","task":"nc-c-mut"}')"
if [[ "$(tok "$base" conf)" == "0.0" && "$(tok "$base" req_eff)" == "3.0" && "$base" == *'arm=glm '* \
   && "$(tok "$mut" conf)" == "0.9" && "$(tok "$mut" req_eff)" == "2.1" && "$mut" == *'arm=glm-flash '* ]]; then
  pass 'NC(c): SRC_CONF default 0.0->0.9 flips conf=0.0->0.9, req_eff=3.0->2.1, and the actual pick glm->glm-flash (FIT_MODE=on)'
else
  fail "NC(c) base=$base mut=$mut"
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
