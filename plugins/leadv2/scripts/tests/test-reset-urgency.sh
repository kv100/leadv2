#!/usr/bin/env bash
# changed-scope triggers, self-registered (scan_suite_triggers convention):
# run-all-triggers: leadv2-route-arbiter
# ARBITER-DECISION-INPUTS-01 D1 — reset proximity ranks wasted quota.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
# CI supplies a writable /private/tmp while its inherited TMPDIR can point at
# an app sandbox that is intentionally unreadable to shell tests.
TMP="$(mktemp -d /private/tmp/test-reset-urgency.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail(){ printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }

cat >"$TMP/routing.yaml" <<'YML'
router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 95, review_pct: 95}}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]
  capability_matrix:
    - {arm: sonnet, provider: claude, model: sonnet, cost: 4.5, protected: true, sizes: [standard], kinds: [code]}
    - {arm: codex, provider: codex, model: codex, cost: 3, protected: true, sizes: [standard], kinds: [code, docs]}
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

# quota <claude_5h_pct> <claude_5h_reset|none> <claude_week_pct>
#       <claude_week_reset|none> <codex_pct> <codex_reset>
quota(){ python3 - "$@" <<'PY'
import json,sys
f5,h5,fw,hw,c,hc=sys.argv[1:]
def window(p,h):
    d={'pct':float(p)}
    if h!='none': d['hours_to_reset']=float(h)
    return d
print(json.dumps({
 'glm': {'status':'ok','five_hour':{'pct':99},'weekly':{'pct':99}},
 'codex': {'status':'ok','binding_window':'weekly','windows':[
   {'kind':'weekly','used_percent':float(c),'limit_window_seconds':604800,'hours_to_reset':float(hc)}]},
 'anthropic': {'status':'ok','accounts':[{'active':True,'status':'ok',
   'five_hour':window(f5,h5),'seven_day':window(fw,hw)}]}
}))
PY
}
run(){ # <case> <quota> <descriptor> [extra env assignments]
  local label="$1" q="$2" d="$3"; shift 3
  env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-$label" \
    LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 \
    ROUTE_TEST_QUOTA="$q" "$@" \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$d"
}
DESC='{"kind":"code","size":"standard","allowed_arms":["sonnet","codex"]}'

# (a) Founder case: Claude's WEEKLY meter has 95% remaining and resets in 5h;
# Codex has 80% remaining but 140h to reset.  Each uses its own 168h period.
# The near weekly quota is preferred despite the 4.5-vs-3 matrix price.
founder_q="$(quota 60 2 5 5 20 140)"
out_a="$(run founder "$founder_q" "$DESC")"
if [[ "$out_a" == arm=sonnet\ * && "$out_a" == *'reset_urgency=claude:1.922[seven_day]'* ]]; then
  pass '(a) founder case: weekly Claude reset in 5h with 95pct left outranks Codex reset in 140h'
else
  fail "(a) expected weekly urgency winner sonnet: $out_a"
fi

# (b) Same clock, but no quota to save: 2% remaining must not buy the arm.
out_b="$(run low-left "$(quota 60 2 98 5 20 140)" "$DESC")"
if [[ "$out_b" == arm=codex\ * ]]; then
  pass '(b) near reset with only 2pct left is not preferred'
else
  fail "(b) low remaining quota gained an undeserved boost: $out_b"
fi

# (c) Absent reset time is neutral, never a free boost.
out_c="$(run unreadable "$(quota 60 100 5 none 20 140)" "$DESC")"
if [[ "$out_c" == arm=codex\ * && "$out_c" != *'reset_urgency=claude:'* ]]; then
  pass '(c) unreadable reset is neutral (no Claude urgency token)'
else
  fail "(c) unreadable reset was not neutral: $out_c"
fi

# (d) A stale cache is not imminent: negative and zero reset values are neutral.
out_dneg="$(run stale-neg "$(quota 60 100 5 -0.1 20 140)" "$DESC")"
out_dzero="$(run stale-zero "$(quota 60 100 5 0 20 140)" "$DESC")"
if [[ "$out_dneg" == arm=codex\ * && "$out_dzero" == arm=codex\ * && "$out_dneg" != *'reset_urgency=claude:'* && "$out_dzero" != *'reset_urgency=claude:'* ]]; then
  pass '(d) negative and zero reset values are neutral, not stale-cache boosts'
else
  fail "(d) stale reset handling neg=$out_dneg zero=$out_dzero"
fi

# (e) Five-hour urgency counts even when weekly (60pct used) is binding.  The
# token names the winning five_hour term; it is not silently discarded because
# the weekly meter supplied the provider-level utilisation value.
out_e="$(run nonbinding-five "$(quota 20 0.25 60 120 20 140)" "$DESC")"
if [[ "$out_e" == arm=sonnet\ * && "$out_e" == *'reset_urgency=claude:1.760[five_hour]'* ]]; then
  pass '(e) non-binding five-hour meter supplies urgency while weekly remains binding'
else
  fail "(e) non-binding five-hour urgency missing or ignored: $out_e"
fi

# (f) The score is deterministic with a frozen fixture and no equal-price tie.
out_f1="$(run deterministic "$founder_q" "$DESC")"
out_f2="$(run deterministic "$founder_q" "$DESC")"
if [[ "$out_f1" == "$out_f2" && "$out_f1" == arm=sonnet\ * ]]; then
  pass '(f) same frozen decision twice is byte-identical (no reset oscillation)'
else
  fail "(f) decision changed across identical runs: first=$out_f1 second=$out_f2"
fi

# (g) Urgency never creates a capability cell: docs exists only for codex.
out_g="$(run incapable "$founder_q" '{"kind":"docs","size":"standard","allowed_arms":["sonnet","codex"]}')"
if [[ "$out_g" == arm=codex\ * && "$out_g" != *'reset_urgency=claude:'* ]]; then
  pass '(g) urgency cannot buy capability: unsupported Claude docs arm is absent'
else
  fail "(g) urgency crossed the capability boundary: $out_g"
fi

# (h) One-flag rollback restores the pre-urgency cost outcome.
out_h="$(run rollback "$founder_q" "$DESC" LEADV2_ARBITER_RESET_URGENCY=0)"
if [[ "$out_h" == arm=codex\ * && "$out_h" != *'reset_urgency='* ]]; then
  pass '(h) kill switch restores cost order and removes urgency provenance'
else
  fail "(h) kill switch did not roll back: $out_h"
fi

# (i) NEGATIVE CONTROL: mutate the code formula on a private copy.  The founder
# case must go red (back to codex), then the unmodified binary must go green.
mut="$TMP/arbiter-without-reset-urgency.sh"
python3 - "$ARBITER" "$mut" <<'PY'
import sys
s=open(sys.argv[1]).read()
old="weight=_RESET_URGENCY_W_MIN+(_RESET_URGENCY_W_MAX-_RESET_URGENCY_W_MIN)*best"
if s.count(old)!=1: raise SystemExit('urgency formula anchor count=%d' % s.count(old))
open(sys.argv[2],'w').write(s.replace(old, 'weight=_RESET_URGENCY_W_MIN'))
PY
if [[ -f "$mut" ]]; then
  out_i="$(env LEADV2_ROUTE_ARBITER_ROUTING_YAML="$TMP/routing.yaml" LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state-mut" LEADV2_ARBITER_SPEND_FORECAST=0 LEADV2_ARBITER_OBSERVED_COST=0 ROUTE_TEST_QUOTA="$founder_q" bash -c 'source "$0"; route_arbiter worker "$1"' "$mut" "$DESC")"
  if [[ "$out_i" == arm=codex\ * ]]; then
    pass '(i RED) removing the urgency formula flips the founder case to codex'
  else
    fail "(i RED) mutation did not flip the decision: $out_i"
  fi
else
  fail '(i) mutation copy was not created'
fi
out_i2="$(run mutation-revert "$founder_q" "$DESC")"
if [[ "$out_i2" == arm=sonnet\ * ]]; then
  pass '(i GREEN) unmutated arbiter restores the founder-case Claude pick'
else
  fail "(i GREEN) reverting mutation did not restore sonnet: $out_i2"
fi

printf 'SUMMARY: pass=%d fail=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
