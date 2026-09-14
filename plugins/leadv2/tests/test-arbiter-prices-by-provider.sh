#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01):
# run-all-triggers: leadv2-route-arbiter leadv2-routing leadv2-launch-registry
#
# test-arbiter-prices-by-provider.sh — PRICE-THE-ARM-PER-PROVIDER-01
# (founder decision 2026-09-13, dispatch-f8880421).
#
# Proves the arbiter prices a candidate by router_v2.cost[price_key(row)]
# (arm name for glm-flash, provider name otherwise), not by the matrix row's
# own (now removed) `cost:` field:
#   (1) positive          — two capable, uncapped arms on different providers;
#                            the cheaper PROVIDER wins, cost_src=...:measured.
#   (2) negative control  — same fixture, provider prices swapped -> the
#                            OTHER arm wins. This is what proves the arbiter
#                            actually READS the price rather than always
#                            picking the same arm for an unrelated reason.
#   (3) null price         — an unpriced provider still gets selected (never
#                            refused) at the median of the numeric entries,
#                            cost_src=...:median.
#   (4) cost: block absent — legacy per-row `cost:` honoured byte-for-byte,
#                            cost_src=...:legacy_row (the 15 pre-existing
#                            scratch-yaml suites depend on exactly this path).
#   (5) max_cost constraint reads the provider price, not the row.
#   (6) malformed price     — non-numeric router_v2.cost entry is a config
#                            error (rc=2, reason=routing_yaml_invalid), never
#                            a silent fallback, and the message names the key.
#   (7) claude/anthropic   — PRICE-KEY-ANTHROPIC-VS-CLAUDE-MISMATCH-01
#       normalization         (dispatch-0144df45, 2026-09-14): a capability_matrix
#                            row with provider: claude (the real matrix's own
#                            spelling for haiku/sonnet/opus/fable) must read
#                            router_v2.cost.anthropic (the real matrix's own
#                            spelling for that price, matching
#                            leadv2-drain-weights.py's fit bucket) --
#                            cost_src=anthropic:measured, not a median
#                            fallback. (7b) is the swapped negative control:
#                            proves the anthropic price is actually READ, not
#                            coincidentally cheapest.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/../scripts" && pwd)"
ARBITER="${LEADV2_TEST_ARBITER_BIN:-${SCRIPTS_DIR}/lib/leadv2-route-arbiter.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
LAST_ASSERT="(none yet)"
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
printf 'arbiter_under_test=%s sha256=%s\n' "$ARBITER" "$(shasum -a 256 "$ARBITER" 2>/dev/null | awk '{print substr($1,1,16)}')"

cat >"$TMP/live.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$ROUTE_TEST_QUOTA"
EOF
cat >"$TMP/free.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/live.sh" "$TMP/free.sh"

quota(){ python3 - "$1" "$2" "$3" <<'PY'
import json,sys
g,c,a=map(int,sys.argv[1:])
print(json.dumps({'glm':{'status':'ok','five_hour':{'pct':g},'weekly':{'pct':g}},'codex':{'status':'ok','binding_window':'primary','windows':[{'kind':'primary','used_percent':c}]},'anthropic':{'status':'ok','accounts':[{'active':True,'status':'ok','five_hour_pct':a,'seven_day_pct':a}]}}))
PY
}
Q="$(quota 13 20 45)"
: >"$TMP/ledger.jsonl"
: >"$TMP/ev-empty.jsonl"

# run <routing.yaml> <descriptor> -> full decision line (stdout+stderr merged)
run(){
  local routing="$1" desc="$2"
  rm -f "$TMP/state"
  env \
    LEADV2_ROUTE_ARBITER_ROUTING_YAML="$routing" \
    LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" \
    LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
    LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" \
    LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL="$TMP/ev-empty.jsonl" \
    ROUTE_ARBITER_FAILURE_LEDGER="$TMP/ledger.jsonl" \
    ROUTE_TEST_QUOTA="$Q" \
    bash -c 'source "$0"; route_arbiter worker "$1"' "$ARBITER" "$desc" 2>&1
}
arm_of(){ printf '%s\n' "$1" | grep -m1 -oE '^arm=[^[:space:]]+' | cut -d= -f2; }
cost_src_of(){ printf '%s\n' "$1" | grep -oE 'cost_src=[^ ]*' | head -1; }

BASE_MATRIX_HDR='router_v2:
  quota_ceilings: {glm: {work_pct: 80, review_pct: 90}, claude: {work_pct: 95, review_pct: 95}, codex: {work_pct: 90, review_pct: 95}}
  observed_cost: {min_rows: 999}
  effort_scale: [none, minimal, low, medium, high, xhigh, max, ultra]
  effort_ceiling: ultra
  effort_matrix: [{default: true, effort: medium}]'

DESC='{"kind":"code","size":"standard","task":"pricebyprovideraabb"}'

# (1) positive: glm cheaper than codex -> glm wins, cost_src measured.
cat >"$TMP/r1.yaml" <<EOF
$BASE_MATRIX_HDR
  cost: {glm: 1.0, codex: 5.0}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
out="$(run "$TMP/r1.yaml" "$DESC")"
if [[ "$(arm_of "$out")" == "glm" && "$(cost_src_of "$out")" == "cost_src=glm:measured" ]]; then
  pass "(1) cheaper provider (glm 1.0 < codex 5.0) wins, cost_src=glm:measured"
else
  fail "(1) got arm=$(arm_of "$out") $(cost_src_of "$out") out=[$out]"
fi

# (2) negative control: swap the two provider prices -> the OTHER arm wins.
cat >"$TMP/r2.yaml" <<EOF
$BASE_MATRIX_HDR
  cost: {glm: 5.0, codex: 1.0}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
out="$(run "$TMP/r2.yaml" "$DESC")"
if [[ "$(arm_of "$out")" == "codex" && "$(cost_src_of "$out")" == "cost_src=codex:measured" ]]; then
  pass "(2) negative control: prices swapped -> arm=codex wins (proves the price is actually read)"
else
  fail "(2) got arm=$(arm_of "$out") $(cost_src_of "$out") out=[$out]"
fi

# (3) null price: only capable arm's provider is unpriced -> still selected,
# never refused, priced at the median of the numeric entries (here: codex's
# 5.0 is the only numeric entry even though codex is not itself a candidate).
cat >"$TMP/r3.yaml" <<EOF
$BASE_MATRIX_HDR
  cost: {glm: null, codex: 5.0}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
out="$(run "$TMP/r3.yaml" "$DESC")"
if [[ "$(arm_of "$out")" == "glm" && "$(cost_src_of "$out")" == "cost_src=glm:median" ]]; then
  pass "(3) null price -> arm still selected (never refused), cost_src=glm:median"
else
  fail "(3) got arm=$(arm_of "$out") $(cost_src_of "$out") out=[$out]"
fi

# (4) router_v2.cost block absent entirely -> legacy per-row cost: honoured,
# byte-for-byte pre-PRICE-THE-ARM-PER-PROVIDER-01 (the 15 scratch-yaml
# suites that predate this feature depend on exactly this fallback).
cat >"$TMP/r4.yaml" <<EOF
$BASE_MATRIX_HDR
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, cost: 5.0, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, cost: 1.0, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
out="$(run "$TMP/r4.yaml" "$DESC")"
if [[ "$(arm_of "$out")" == "codex" && "$(cost_src_of "$out")" == "cost_src=codex:legacy_row" ]]; then
  pass "(4) cost: block absent -> legacy row cost honoured, cost_src=codex:legacy_row"
else
  fail "(4) got arm=$(arm_of "$out") $(cost_src_of "$out") out=[$out]"
fi

# (5) max_cost caller constraint reads the PROVIDER price: against r1
# (glm=1.0, codex=5.0), max_cost=2 excludes codex (5.0 > 2), leaving glm.
DESC5='{"kind":"code","size":"standard","task":"pricebyprovideraabb","max_cost":2}'
out="$(run "$TMP/r1.yaml" "$DESC5")"
if [[ "$(arm_of "$out")" == "glm" && "$out" == *"arm_excluded=codex:caller_constraint"* ]]; then
  pass "(5) max_cost=2 excludes codex (provider price 5.0 > 2) -> arm=glm"
else
  fail "(5) got arm=$(arm_of "$out") out=[$out]"
fi
# Same constraint against r2 (glm=5.0, codex=1.0): max_cost=2 now excludes
# glm instead -- proves the exclusion tracks the PRICE, not a fixed arm.
DESC5b='{"kind":"code","size":"standard","task":"pricebyprovideraabb","max_cost":2}'
out2="$(run "$TMP/r2.yaml" "$DESC5b")"
if [[ "$(arm_of "$out2")" == "codex" && "$out2" == *"arm_excluded=glm:caller_constraint"* ]]; then
  pass "(5b) same max_cost against swapped prices -> exclusion flips to arm=codex"
else
  fail "(5b) got arm=$(arm_of "$out2") out=[$out2]"
fi

# (6) malformed router_v2.cost entry -> config error, never a silent
# fallback, and the message names the offending key.
cat >"$TMP/r6.yaml" <<EOF
$BASE_MATRIX_HDR
  cost: {glm: 1.0, codex: cheap}
  capability_matrix:
    - {arm: glm, provider: glm, model: glm-5.3, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: codex, provider: codex, model: gpt-5.6-terra, tier: standard, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
set +e
out="$(run "$TMP/r6.yaml" "$DESC")"
rc=$?
set -e 2>/dev/null || true
if [[ $rc -ne 0 && "$out" == *"routing_yaml_invalid"* && "$out" == *"cost.codex"* ]]; then
  pass "(6) malformed router_v2.cost.codex -> rc=$rc, reason=routing_yaml_invalid names the key"
else
  fail "(6) got rc=$rc out=[$out]"
fi

# (7) PRICE-KEY-ANTHROPIC-VS-CLAUDE-MISMATCH-01: a row shaped exactly like
# the real matrix's claude-family rows (provider: claude) must be priced off
# router_v2.cost.anthropic (the real matrix's own key for that price), not
# fall through to the median because price_key(row) returned "claude" and
# found nothing under it.
cat >"$TMP/r7.yaml" <<EOF
$BASE_MATRIX_HDR
  cost: {anthropic: 1.0, glm: 5.0}
  capability_matrix:
    - {arm: sonnet, provider: claude, model: sonnet, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: glm, provider: glm, model: glm-5.3, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
out="$(run "$TMP/r7.yaml" "$DESC")"
if [[ "$(arm_of "$out")" == "sonnet" && "$(cost_src_of "$out")" == "cost_src=anthropic:measured" ]]; then
  pass "(7) provider: claude row prices off cost.anthropic (1.0 < glm 5.0) -> arm=sonnet, cost_src=anthropic:measured"
else
  fail "(7) got arm=$(arm_of "$out") $(cost_src_of "$out") out=[$out]"
fi

# (7b) negative control: swap the two prices -> the OTHER arm wins. If
# price_key(row) still returned the unnormalized "claude" and missed
# cost.anthropic entirely, this would misfire identically to (7) (median
# fallback both times) instead of tracking the swap -- this is what proves
# the anthropic price is actually READ, not coincidentally cheapest.
cat >"$TMP/r7b.yaml" <<EOF
$BASE_MATRIX_HDR
  cost: {anthropic: 5.0, glm: 1.0}
  capability_matrix:
    - {arm: sonnet, provider: claude, model: sonnet, kinds: [code], sizes: [standard], protected: true, capability: 4}
    - {arm: glm, provider: glm, model: glm-5.3, kinds: [code], sizes: [standard], protected: true, capability: 4}
EOF
out="$(run "$TMP/r7b.yaml" "$DESC")"
if [[ "$(arm_of "$out")" == "glm" && "$(cost_src_of "$out")" == "cost_src=glm:measured" ]]; then
  pass "(7b) negative control: prices swapped -> arm=glm wins (proves cost.anthropic is actually read for provider: claude)"
else
  fail "(7b) got arm=$(arm_of "$out") $(cost_src_of "$out") out=[$out]"
fi

printf 'SUMMARY pass=%d fail=%d\n' "$PASS" "$FAIL"
SUMMARY_PRINTED=1
[[ $FAIL -eq 0 ]]
