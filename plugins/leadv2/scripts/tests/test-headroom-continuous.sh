#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
# test-headroom-continuous.sh — W1-GRANULARITY-CONTINUOUS-HEADROOM-01 (founder
# order 2026-09-10) as superseded and re-pinned by
# WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01 (founder order 2026-09-16;
# cause class test_encodes_superseded_requirement for every case below that
# used to pin the usable_now rate ramp).
#
# History: the 2026-09-10 order replaced the router_v2.headroom_weights STEP
# TABLE with ONE monotone bounded ramp, w(u) = 0.2 + 0.8*min(u,8)/8 on
# usable_now. THE-BALANCER-CONCENTRATES-ON-THE-EMPTIEST-BUCKET-01 (founder,
# 2026-09-14) then moved >=24h-period windows to a period-invariant remaining
# FRACTION, leaving the ramp's domain exactly the five-hour-scale rates. The
# 2026-09-16 order ended that too: the weekly window is the ALLOCATION KEY,
# the five-hour window is an ADMISSION constraint — "can this arm take work
# right now", never "who deserves this task" — so a five-hour rate may not
# rank at all. The ramp and _HEADROOM_U_SAT are deleted from the arbiter;
# headroom_weight prices the worst readable LONG-period window's remaining
# fraction (the 2026-09-14 reserve, now the only ranking signal here).
#
# This suite pins the five acceptance facts in their post-2026-09-16 form:
#   1. SEPARATION (the RED-ON-NEUTRALISED-CODE control): two weekly states
#      that a neutralised reserve prices identically (90% vs 10% used) must
#      receive DIFFERENT weights, exactly on the reserve formula.
#   2. MONOTONICITY on an ordered sample, never two points: weight matches
#      the reserve formula point by point, never increases as used rises,
#      strictly decreasing everywhere (no flat stretch, no steps).
#   3. EDGES do not move and the new boundary holds:
#      a) weekly 0% used -> weight exactly 1.0 (winner journalled claude:1,
#         cost unscaled);
#      b) FIVE-HOUR NEUTRALITY: a burnt five_hour (90% used) and a fresh one
#         (10%) price the SAME weekly-reserve weight — the 2026-09-16 guard;
#      c) FIVE-HOUR STILL ADMITS: a five_hour over the ceiling excludes the
#         arm by the capped cliff — admission kept its real job;
#      d) an unmetered hand -> 0.2 floor, named loudly, not journalled into
#         headroom_priced.
#   4. REFUSALS STAY DISCRETE: over-ceiling -> arm_excluded=<arm>:capped; all
#      measured providers capped -> arm=refuse reason=all_arms_capped.
#      Continuity lives ONLY in the ranking key; a human can still predict a
#      refusal without running the arbiter.
#   5. NO DEAD KEY: grep -c headroom_weights on the live config = 0.
#
# Hermeticity: a private routing yaml with explicit per-row costs, and the
# events journal PINNED to an empty file — measured 2026-09-16 on this tree,
# the un-pinned suite read the host's live journal
# (~/.claude/cache/leadv2-events/leadv2.jsonl) and three edge cases went
# environment-dependent red (cost_actuals n=4/n=5 and forecast p75s from 202
# live durations). The arbiter documents the seam (:137 region): an explicit
# LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL always wins.
#
# Negative control: neutralising the long-period filter inside _long_window
# must redden the separation case. Artifacts: the (mut RED)/(mut GREEN) cases.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
ROUTING_LIVE="${SCRIPTS_DIR}/../config/leadv2-routing.yaml"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

# sonnet (2.5) under codex (3.0): the WINNER names which weight claude got —
# at the 0.2 floor sonnet prices 12.5 (codex wins), at full headroom 2.5
# (sonnet wins). glm at 1.0 sits capped at 99 in every fixture that keeps it.
cat >"$TMP/routing.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 95, review_pct: 95}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 95, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  capability_matrix:
    - {arm: sonnet, provider: claude, model: sonnet, cost: 2.5, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: codex, cost: 3.0, protected: true, sizes: [standard], kinds: [code]}
    - {arm: glm, provider: glm, model: glm-5.3, cost: 1.0, protected: true, sizes: [standard], kinds: [code]}
YML
cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"
: >"$TMP/journal"   # pinned empty: no host durations, no cost actuals
run(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" \
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/journal" \
  ROUTE_TEST_QUOTA="$1" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "${2:-$ARBITER}" '{"work_kind":"code","size":"standard","task":"t"}'; }

# The reserve formula, stated once, computed by the SAME float expression
# (and in the same order) as headroom_weight in the arbiter, so a 1-ulp
# difference can never make this suite disagree with the code it pins.
reserve_w(){ python3 - "$1" <<'PY'
import sys
w_min,w_max=0.2,1.0
p=float(sys.argv[1])
print('%g' % (w_min+(w_max-w_min)*(100.0-p)/100.0))
PY
}

# claude is the observed provider: five_hour <five_pct>/<five_h> plus
# seven_day <seven_pct>/100h. codex sits on a period-unknown 'primary' window
# (neutral: no readable long window -> weight 1.0), glm is capped at 99, so
# the claude token and the sonnet-vs-codex contest stay deterministic.
qc(){ python3 - "$@" <<'PY'
import json,sys
seven=float(sys.argv[1]); five=float(sys.argv[2]) if len(sys.argv)>2 else 20.0
five_h=float(sys.argv[3]) if len(sys.argv)>3 else 100.0
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':99},'weekly':{'pct':99}},
 'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':20}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok',
   'five_hour':{'pct':five,'hours_to_reset':five_h},
   'seven_day':{'pct':seven,'hours_to_reset':100.0}}]}}))
PY
}
# plain three-way used-percentage fixture (the refusal cases)
qpct(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},
 'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok',
   'five_hour':{'pct':a},'seven_day':{'pct':a}}]}}))
PY
}
# an unmetered claude hand: no readable window at all, account_state produced
# upstream. The 0.2 floor is APPLIED but (as before 2026-09-16) not journalled
# into headroom_priced -- the hand is named by claude_account_state=unmetered
# / claude_priced_from instead. Discriminating fixture: at the floor sonnet
# prices 2.5/0.2=12.5 (codex 3.0 wins); if the floor silently became 1.0,
# sonnet at 2.5 wins -- the winner names the weight.
qunmet(){ python3 - <<'PY'
import json
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':99},'weekly':{'pct':99}},
 'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':20}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'usage_failed','account_state':'unmetered'}]}}))
PY
}
cl_token(){ printf '%s\n' "$1" | sed -n 's/.*headroom_priced=\([^ ]*\).*/\1/p' | tr ',' '\n' | sed -n 's/^claude://p'; }

# ── 1. SEPARATION ────────────────────────────────────────────────────────────
# weekly 90% vs 10% used: a neutralised reserve prices both 0.5; the real
# reserve must price them apart, exactly on the formula. Named mutation case.
rm -f "$TMP/state"
out90="$(run "$(qc 90)" || true)"
rm -f "$TMP/state"
out10="$(run "$(qc 10)" || true)"
t90="$(cl_token "$out90")"; t10="$(cl_token "$out10")"
if [[ -n "$t90" && -n "$t10" && "$t90" != "$t10" && "$t90" == "$(reserve_w 90)" && "$t10" == "$(reserve_w 10)" ]]; then
  pass "separation: weekly 90% -> $t90, 10% -> $t10 (one basket on neutralised code, two prices now)"
else
  fail "separation: t90=$t90 t10=$t10 (expected $(reserve_w 90) / $(reserve_w 10)); out90=$out90 out10=$out10"
fi
# The founder-measured pair (glm 83%/36.8h vs 17%/100h in
# THE-BALANCER-CONCENTRATES-ON-THE-EMPTIEST-BUCKET-01), asserted too: 83 vs 17.
rm -f "$TMP/state"
out17="$(run "$(qc 17)" || true)"
t17="$(cl_token "$out17")"
if [[ -n "$t17" && "$t17" != "$t90" && "$t17" == "$(reserve_w 17)" ]]; then
  pass "separation (founder pair): weekly 90% -> $t90, 17% -> $t17"
else
  fail "separation 90-vs-17: t90=$t90 t17=$t17 (expected $(reserve_w 17)); out17=$out17"
fi

# ── 2. MONOTONICITY on an ordered sample ─────────────────────────────────────
# 0..90 only: at >=95 used the binding window crosses the work ceiling and
# the arm is excluded by the capped cliff BEFORE pricing, so no weight exists
# to sample (that boundary is case 3c's, not this one's).
: >"$TMP/sweep.txt"
for p in 0 5 10 20 30 40 50 60 70 80 90; do
  rm -f "$TMP/state"
  out="$(run "$(qc "$p")" || true)"
  w="$(cl_token "$out")"; [[ -n "$w" ]] || w=1.0   # no token == weight exactly 1.0
  printf '%s %s\n' "$p" "$w" >>"$TMP/sweep.txt"
done
sweep_verdict="$(python3 - "$TMP/sweep.txt" <<'PY'
import sys
w_min,w_max=0.2,1.0
def exp(p): return w_min+(w_max-w_min)*(100.0-p)/100.0
rows=[tuple(map(float,l.split())) for l in open(sys.argv[1]) if l.strip()]
bad=[(p,w,exp(p)) for p,w in rows if abs(w-exp(p))>1e-9]
mono=all(rows[i][1]>=rows[i+1][1] for i in range(len(rows)-1))
strict=all(rows[i][1]>rows[i+1][1] for i in range(len(rows)-1))
detail=''
if bad: detail+=' formula-mismatch at %s;' % ','.join('%g->%g(!=%g)'%b for b in bad)
if not mono: detail+=' non-monotone;'
if not strict: detail+=' flat stretch;'
print('ok' if not detail else detail.strip())
PY
)"
if [[ "$sweep_verdict" == ok ]]; then
  pass 'monotonicity: 11-point ordered sample matches the reserve, never increases with use, strictly decreasing'
else
  fail "monotonicity: $sweep_verdict (sweep: $(tr '\n' ';' <"$TMP/sweep.txt"))"
fi

# ── 3. EDGES ─────────────────────────────────────────────────────────────────
rm -f "$TMP/state"
outfull="$(run "$(qc 0)" || true)"
# No headroom_priced token at all: the winner is priced at EXACTLY 1.0 and,
# with no other priced arm in the chain, the winner-journalling setdefault
# does not fire (the absence case test-route-arbiter.sh (g6) pins). The
# winner's own headroom_w=1 names the unscaled price on the line.
if [[ -z "$(cl_token "$outfull")" && "$outfull" == *'arm=sonnet '* && "$outfull" == *' headroom_w=1 '* ]]; then
  pass 'edge weekly 0% used: weight exactly 1.0 (no token, headroom_w=1) and sonnet wins unscaled'
else
  fail "edge weekly 0%: out=$outfull"
fi
# five-hour neutrality (the 2026-09-16 guard): burnt (90%/5h — ramp 0.4 on
# pre-order code) vs fresh (10%/5h — ramp saturated) five_hour, same weekly
# 20% used -> identical weekly-priced weight AND identical winner.
rm -f "$TMP/state"
out_burnt="$(run "$(qc 20 90 5)" || true)"
rm -f "$TMP/state"
out_fresh="$(run "$(qc 20 10 5)" || true)"
if [[ "$(cl_token "$out_burnt")" == "$(reserve_w 20)" && "$(cl_token "$out_fresh")" == "$(reserve_w 20)" \
      && "$out_burnt" == 'arm=sonnet '* && "$out_fresh" == 'arm=sonnet '* ]]; then
  pass "edge five-hour neutrality: burnt and fresh five_hour both price claude:$(reserve_w 20) from weekly alone, same winner"
else
  fail "edge five-hour neutrality: burnt=$out_burnt fresh=$out_fresh"
fi
# five-hour still ADMITS: five_hour 99% used binds over the ceiling -> the
# capped cliff excludes the arm. Admission is the five-hour window's whole
# remaining job, and it lives here (before ecost), not in the score.
rm -f "$TMP/state"
outadm="$(run "$(qc 20 99 5)" || true)"
if [[ "$outadm" == *'sonnet:capped'* && "$outadm" != *'arm=sonnet '* ]]; then
  pass 'edge five-hour admits: over-ceiling five_hour excludes the arm by the capped cliff'
else
  fail "edge five-hour admission lost: out=$outadm"
fi
rm -f "$TMP/state"
outu="$(run "$(qunmet)" || true)"
cl_tok="$(cl_token "$outu")"
if [[ "$outu" == *'arm=codex '* && "$outu" == *'claude_account_state=unmetered'* && "$outu" == *'claude_priced_from=configured_allowance_conservative'* && -z "$cl_tok" ]]; then
  pass 'edge no-data (unmetered): sonnet priced at the 0.2 floor (codex 3.0 beat 12.5), hand named, not in headroom_priced'
else
  fail "edge unmetered: out=$outu cl_tok=$cl_tok"
fi

# ── 4. REFUSALS STAY DISCRETE ────────────────────────────────────────────────
rm -f "$TMP/state"
outc="$(run "$(qpct 20 99 20)" || true)"
if [[ "$outc" == *'arm_excluded=codex:capped'* && "$outc" != *'arm=codex '* ]]; then
  pass 'discrete refusal: codex over work ceiling excluded by the same cliff (arm_excluded=codex:capped)'
else
  fail "discrete over-ceiling: out=$outc"
fi
rm -f "$TMP/state"
outr="$(run "$(qpct 99 99 99)" || true)"
if [[ "$outr" == *'arm=refuse '* && "$outr" == *'reason=all_arms_capped'* ]]; then
  pass 'discrete refusal: all measured providers capped -> arm=refuse reason=all_arms_capped'
else
  fail "discrete all-capped: out=$outr"
fi

# ── 5. NO DEAD KEY ───────────────────────────────────────────────────────────
n="$(grep -c 'headroom_weights' "$ROUTING_LIVE" || true)"
if [[ "${n:-1}" == 0 ]]; then
  pass 'config: headroom_weights key deleted (grep -c = 0), no dead key left in the live config'
else
  fail "config: headroom_weights still present (grep -c = $n)"
fi

# ── NEGATIVE CONTROL ─────────────────────────────────────────────────────────
# Drop the long-period filter inside _long_window on a private copy: the
# five_hour window (20% used) then out-binds seven_day (10%) and the
# separation fixture's weight moves off the weekly reserve (0.92 -> 0.84).
# The unmodified binary must price it back to 0.92.
mut="$TMP/arbiter-without-long-filter.sh"
python3 - "$ARBITER" "$mut" <<'PY'
import sys
s=open(sys.argv[1]).read()
old="        if _period is None or _period<_HEADROOM_LONG_PERIOD_HOURS: continue"
if s.count(old)!=1: raise SystemExit('long-filter anchor count=%d' % s.count(old))
open(sys.argv[2],'w').write(s.replace(old, '        if _period is None: continue'))
PY
if [[ -f "$mut" ]]; then
  rm -f "$TMP/state"
  outm="$(run "$(qc 10 20 100)" "$mut" || true)"
  tm="$(cl_token "$outm")"
  if [[ "$tm" == '0.84' ]]; then
    pass '(mut RED) unfiltered _long_window prices claude:0.84 from five_hour (weekly reserve said 0.92)'
  else
    fail "(mut RED) mutation did not re-admit the five_hour rate: tm=$tm out=$outm"
  fi
else
  fail '(mut) mutation copy was not created'
fi
rm -f "$TMP/state"
outg="$(run "$(qc 10 20 100)" || true)"
if [[ "$(cl_token "$outg")" == "$(reserve_w 10)" ]]; then
  pass "(mut GREEN) unmodified arbiter prices the weekly reserve ($(reserve_w 10))"
else
  fail "(mut GREEN) unmodified arbiter moved off the weekly reserve: out=$outg"
fi

printf 'SUMMARY: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
