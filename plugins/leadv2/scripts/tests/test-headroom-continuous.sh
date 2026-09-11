#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml
# test-headroom-continuous.sh — W1-GRANULARITY-CONTINUOUS-HEADROOM-01 (founder
# order 2026-09-10, PRE-WAVES-PLAN §1.6: "the buckets ARE the dumbness").
#
# The arbiter's inputs are continuous; the old router_v2.headroom_weights STEP
# TABLE quantised the decision into four rows whose third (min_usable_now: 0 ->
# 0.4) swallowed almost the whole range (live 2026-09-10: three providers in
# one basket at once). It is replaced by ONE monotone bounded ramp inside
# headroom_weight:
#
#     w(u) = 0.2 + 0.8 * min(u, 8) / 8        (u = usable_now)
#
# clipped to [0.2, 1.0] — a saturating linear ramp with the SAME edges the
# table gave (1.0 at u >= 8, 0.2 for an unmetered hand) and no step
# discontinuities. This suite pins the five acceptance facts:
#   1. SEPARATION (the RED-ON-STEPPED-CODE control): two hands in what used to
#      be ONE basket -- u=0.5 and u=1.5, both -> weight 0.4 on the stepped
#      code (measured on this tree 2026-09-10) -- must receive DIFFERENT
#      effective prices. This is the NAMED test for the mutation control: a
#      stepped basket re-introduced inside headroom_weight must make exactly
#      this case fail. The brief's example pair 0.5/7.0 is asserted as well,
#      but on this tree's 4-row table u=7.0 already read 0.7, so it never was
#      the same-bucket pair; 0.5/1.5 is.
#   2. MONOTONICITY on an ordered sample, never two points: weight matches the
#      ramp formula point by point, never decreases across the sample, and
#      strictly increases while u < 8.
#   3. EDGES do not move: u >= 8 -> weight exactly 1.0 (no headroom_priced
#      token, cost unscaled); an unmetered hand -> 0.2 (the table's null row,
#      now the ramp floor).
#   4. REFUSALS STAY DISCRETE (§1.6 boundary, half the assignment): an
#      over-ceiling provider is excluded by the same CLIFF as before the ramp
#      -- arm_excluded=<arm>:capped; all measured providers capped ->
#      arm=refuse reason=all_arms_capped. Continuity lives ONLY in the ranking
#      key; a human can still predict a refusal without running the arbiter.
#   5. NO DEAD KEY: grep -c headroom_weights on the live config = 0. A live
#      config carrying a dead key is a lie to the reader.
#
# Negative control: leadv2-mutation-control.sh mutating _headroom_ramp's return
# back to a stepped basket must turn case 1 red. Artifacts live under
# docs/handoff/w1-granularity-continuous-headroom/mutation-control/.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
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
run(){ LEADV2_ROUTE_ARBITER_ROUTING_YAML="$ROUTING" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
  LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
  ROUTE_TEST_QUOTA="$1" ROUTE_TEST_FREE_RC="${2:-0}" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$3"; }

# The ramp formula, stated once, computed by the SAME float expression (and in
# the same order) as _headroom_ramp in the arbiter, so a 1-ulp difference can
# never make this suite disagree with the code it pins.
ramp_w(){ python3 - "$1" <<'PY'
import sys
w_min,w_max,sat=0.2,1.0,8.0
u=float(sys.argv[1])
print('%g' % (w_min+(w_max-w_min)*min(u,sat)/sat))
PY
}

# codex is the observed provider: single primary window, usable_now injected
# verbatim. glm sits capped at 99 (excluded by its ceiling, no usable_now) and
# claude is healthy at 20/h, so codex-vs-sonnet is the only priced contest and
# the decision line stays deterministic (cost 3 vs 5).
qcx(){ python3 - "$1" <<'PY'
import json,sys
cx=float(sys.argv[1])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':99},'weekly':{'pct':99}},
 'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':20,'usable_now':cx}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour':{'pct':20,'usable_now':20.0},'seven_day':{'pct':20,'usable_now':20.0}}]}}))
PY
}
# plain three-way used-percentage fixture (the refusal cases)
qpct(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},
 'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c,'usable_now':5.0}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour':{'pct':a,'usable_now':5.0},'seven_day':{'pct':a,'usable_now':5.0}}]}}))
PY
}
# an unmetered claude hand: no readable window at all, account_state produced
# upstream. The table's null row (weight 0.2) covered this; the ramp floor
# covers it now. The weight is APPLIED but (as on the stepped code) not
# journalled into headroom_priced -- the hand is named by
# claude_account_state=unmetered / claude_priced_from instead.
# Discriminating fixture: codex at u=0.1 prices ~10.7 (3/0.28 on the ramp,
# 7.5 on the stepped table) -- strictly between sonnet at weight 0.2 (25.0)
# and sonnet at weight 1.0 (5.0), so the WINNER names the weight sonnet got:
# codex => unmetered was priced 0.2; sonnet => it silently became 1.0.
qunmet(){ python3 - <<'PY'
import json
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':99},'weekly':{'pct':99}},
 'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':20,'usable_now':0.1}]},
 'anthropic':{'status':'ok','accounts':[{'active':True,'status':'usage_failed','account_state':'unmetered'}]}}))
PY
}
cx_token(){ printf '%s\n' "$1" | sed -n 's/.*headroom_priced=\([^ ]*\).*/\1/p' | tr ',' '\n' | sed -n 's/^codex://p'; }

# ── 1. SEPARATION ────────────────────────────────────────────────────────────
# u=0.5 and u=1.5 were ONE basket (both 0.4) on the stepped code; the ramp must
# price them apart. This is the named mutation-control test.
rm -f "$TMP/state"
out05="$(run "$(qcx 0.5)" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
rm -f "$TMP/state"
out15="$(run "$(qcx 1.5)" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
t05="$(cx_token "$out05")"; t15="$(cx_token "$out15")"
if [[ -n "$t05" && -n "$t15" && "$t05" != "$t15" && "$t05" == "$(ramp_w 0.5)" && "$t15" == "$(ramp_w 1.5)" ]]; then
  pass "separation: u=0.5 -> $t05, u=1.5 -> $t15 (one basket before, two prices now)"
else
  fail "separation: t05=$t05 t15=$t15 (expected $(ramp_w 0.5) / $(ramp_w 1.5)); out05=$out05 out15=$out15"
fi
# The brief's named example pair, asserted too: 0.5 vs 7.0 differ (on this
# tree's 4-row table they already did -- 0.4 vs 0.7 -- so this is a gradient
# pin, not the red control).
rm -f "$TMP/state"
out70="$(run "$(qcx 7.0)" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
t70="$(cx_token "$out70")"
if [[ -n "$t70" && "$t70" != "$t05" && "$t70" == "$(ramp_w 7.0)" ]]; then
  pass "separation (brief's pair): u=0.5 -> $t05, u=7.0 -> $t70"
else
  fail "separation 0.5-vs-7.0: t05=$t05 t70=$t70 (expected $(ramp_w 7.0)); out70=$out70"
fi

# ── 2. MONOTONICITY on an ordered sample ─────────────────────────────────────
: >"$TMP/sweep.txt"
for u in 0 0.5 1 1.5 2 2.5 3 4 5 6 7 7.5 8 9 12; do
  rm -f "$TMP/state"
  out="$(run "$(qcx "$u")" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
  w="$(cx_token "$out")"; [[ -n "$w" ]] || w=1.0   # no token == weight exactly 1.0
  printf '%s %s\n' "$u" "$w" >>"$TMP/sweep.txt"
done
sweep_verdict="$(python3 - "$TMP/sweep.txt" <<'PY'
import sys
w_min,w_max,sat=0.2,1.0,8.0
def exp(u): return w_min+(w_max-w_min)*min(u,sat)/sat
rows=[tuple(map(float,l.split())) for l in open(sys.argv[1]) if l.strip()]
bad=[(u,w,exp(u)) for u,w in rows if abs(w-exp(u))>1e-9]
mono=all(rows[i][1]<=rows[i+1][1] for i in range(len(rows)-1))
strict=all(rows[i][1]<rows[i+1][1] for i in range(len(rows)-1)
           if rows[i][0]<sat and rows[i+1][0]<sat)
detail=''
if bad: detail+=' formula-mismatch at %s;' % ','.join('%g->%g(!=%g)'%b for b in bad)
if not mono: detail+=' non-monotone;'
if not strict: detail+=' flat stretch below saturation;'
print('ok' if not detail else detail.strip())
PY
)"
if [[ "$sweep_verdict" == ok ]]; then
  pass 'monotonicity: 15-point ordered sample matches the ramp, never decreases, strictly increasing below saturation'
else
  fail "monotonicity: $sweep_verdict (sweep: $(tr '\n' ';' <"$TMP/sweep.txt"))"
fi

# ── 3. EDGES ─────────────────────────────────────────────────────────────────
for u in 8 20; do
  rm -f "$TMP/state"
  out="$(run "$(qcx "$u")" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
  if [[ -z "$(cx_token "$out")" && "$out" == *'arm=codex '* ]]; then
    pass "edge u>=$u: weight exactly 1.0 (no token) and codex wins unscaled"
  else
    fail "edge u>=$u: out=$out"
  fi
done
rm -f "$TMP/state"
outu="$(run "$(qunmet)" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
cl_tok="$(printf '%s' "$outu" | sed -n 's/.*headroom_priced=\([^ ]*\).*/\1/p' | tr ',' '\n' | sed -n 's/^claude://p')"
if [[ "$outu" == *'arm=codex '* && "$outu" == *'claude_account_state=unmetered'* && "$outu" == *'claude_priced_from=configured_allowance_conservative'* && -z "$cl_tok" ]]; then
  pass 'edge no-data (unmetered): sonnet priced at the 0.2 floor (codex ~10.7 beat it), hand named, not in headroom_priced'
else
  fail "edge unmetered: out=$outu cl_tok=$cl_tok"
fi

# ── 4. REFUSALS STAY DISCRETE ────────────────────────────────────────────────
rm -f "$TMP/state"
outc="$(run "$(qpct 20 99 20)" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
if [[ "$outc" == *'arm_excluded=codex:capped'* && "$outc" != *'arm=codex '* ]]; then
  pass 'discrete refusal: codex over work ceiling excluded by the same cliff (arm_excluded=codex:capped)'
else
  fail "discrete over-ceiling: out=$outc"
fi
rm -f "$TMP/state"
outr="$(run "$(qpct 99 99 99)" 1 '{"work_kind":"code","size":"standard","task":"t"}' || true)"
if [[ "$outr" == *'arm=refuse '* && "$outr" == *'reason=all_arms_capped'* ]]; then
  pass 'discrete refusal: all measured providers capped -> arm=refuse reason=all_arms_capped'
else
  fail "discrete all-capped: out=$outr"
fi

# ── 5. NO DEAD KEY ───────────────────────────────────────────────────────────
n="$(grep -c 'headroom_weights' "$ROUTING" || true)"
if [[ "${n:-1}" == 0 ]]; then
  pass 'config: headroom_weights key deleted (grep -c = 0), no dead key left in the live config'
else
  fail "config: headroom_weights still present (grep -c = $n)"
fi

printf 'SUMMARY: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
