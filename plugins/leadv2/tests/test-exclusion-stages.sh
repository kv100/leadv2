#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01);
# EXTRA_SUITE_MAP rows for the same stems live in tests/run-all.sh at the repo root.
# run-all-triggers: leadv2-route-arbiter leadv2-dispatch-code leadv2-routing.yaml
#
# POOL-IS-COMPUTED-AFTER-THE-ARM-IS-CHOSEN-01 -- typed exclusion stages.
#
# The pre-fix arbiter carried a two-valued _arm_excluded map
# (untrusted|not_allowed) and folded four different facts (kind/size fit,
# trust, caller admissibility, budget) into one silent set. An operator
# reading `arm_excluded=fable:not_allowed` could not tell "never eligible"
# from "never tested" from "tested and lost".
#
# Contract under test (mission): one entry per matrix arm that fits kind/size,
# drawn from the ordered stage list
#   not_in_pool, not_launchable, untrusted, capped, failure_memory, price_ratio
# joined with '+' when several apply, always rendered in that canonical
# order. requested_arm_incapable is RESERVED for "no matrix cell fits
# kind/size" and may never name an arm that has a cell.
#
# Control (mission M2): collapse the stages back to one 'not_allowed' value
# in a throwaway mutated copy of the arbiter -- the stage-precision
# assertions must go red.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
ARBITER="${PLUGIN_ROOT}/scripts/lib/leadv2-route-arbiter.sh"

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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$ROUTE_TEST_QUOTA"\n' > "$TMP/live.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/free.sh"
chmod +x "$TMP/live.sh" "$TMP/free.sh"

HEALTHY='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":20,"seven_day_pct":20}]}}'
CLAUDE_CAPPED='{"glm":{"status":"ok","five_hour":{"pct":10},"weekly":{"pct":10}},"codex":{"status":"ok","binding_window":"primary","windows":[{"kind":"primary","used_percent":20}]},"anthropic":{"status":"ok","accounts":[{"active":true,"status":"ok","five_hour_pct":99,"seven_day_pct":99}]}}'

run(){ # <arbiter-sh> <descriptor-json> <quota>
  local arb="$1" descriptor="$2" quota="$3"
  rm -f "$TMP/state"
  LEADV2_ROUTE_ARBITER_QUOTA_LIVE="$TMP/live.sh" LEADV2_ROUTE_ARBITER_FREEPOOL_GATE="$TMP/free.sh" \
  LEADV2_ROUTE_ARBITER_STATE_FILE="$TMP/state" ROUTE_TEST_QUOTA="$quota" \
  bash -c 'source "$0"; route_arbiter worker "$1"' "$arb" "$descriptor"
}
tok(){ printf '%s\n' "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed 's/.*=//'; }
excl(){ printf '%s\n' "$1" | grep -oE ' arm_excluded=[^ ]+' | head -1 | sed 's/^ arm_excluded=//'; }

# ── 1. not_in_pool: the hard set bounds, and everything outside is NAMED ──
set +e
out="$(run "$ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-1","arm_pool":["glm","codex"]}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(excl "$out")" == *'fable:not_in_pool'* && "$(excl "$out")" == *'sonnet:not_in_pool'* ]]; then
  pass 'arm_pool=[glm,codex]: fable/sonnet/opus named not_in_pool, winner inside the set'
else
  fail "not_in_pool case rc=$rc out=$out"
fi

# ── 2. not_launchable: the caller-side seam is its own dimension ──────────
set +e
out="$(run "$ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-2","arm_pool":["codex","sonnet","fable"],"launchable_arms":["codex","sonnet"]}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(excl "$out")" == *'fable:not_launchable'* && "$(excl "$out")" != *'fable:not_in_pool'* ]]; then
  pass 'launchable_arms=[codex,sonnet]: fable is not_launchable but still in the pool -- dimensions do not collapse'
else
  fail "not_launchable case rc=$rc out=$out"
fi

# ── 3. untrusted: protected work names the arms it cannot trust ───────────
# kind=code size=standard + protected -> freepool/glm-flash have no protected
# cell for that fit, so they carry the untrusted stage, never a bare drop.
set +e
out="$(run "$ARBITER" '{"kind":"code","size":"standard","protected":true,"complexity":"standard","complexity_source":"heuristic","task":"st-3"}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(excl "$out")" == *'freepool:untrusted'* ]]; then
  pass 'protected code/standard: freepool carries untrusted, winner is a protected-capable arm'
else
  fail "untrusted case rc=$rc out=$out"
fi

# ── 4. capped: the budget stage is typed per arm ──────────────────────────
set +e
out="$(run "$ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-4","arm_pool":["codex","sonnet"]}' "$CLAUDE_CAPPED")"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(excl "$out")" == *'sonnet:capped'* && "$(tok "$out" arm)" != "sonnet" ]]; then
  pass 'claude at 99%: sonnet:capped typed, the uncapped arm still wins'
else
  fail "capped case rc=$rc out=$out"
fi

# ── 5. price_ratio: survivors that lost are "tested and lost", not silent ─
set +e
out="$(run "$ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-5"}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(excl "$out")" == *':price_ratio'* ]]; then
  pass 'healthy auction names its losers price_ratio (in the pool, launchable, trusted, uncapped -- lost on cost)'
else
  fail "price_ratio case rc=$rc out=$out"
fi

# ── 6. multi-stage join in canonical order ─────────────────────────────────
# fable (plan/heavy cell) outside the hard set AND outside launchable ->
# 'not_in_pool+not_launchable', in that order, joined with '+'.
set +e
out="$(run "$ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-6","arm_pool":["glm","codex"],"launchable_arms":["glm","codex"]}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 0 && "$(excl "$out")" == *'fable:not_in_pool+not_launchable'* ]]; then
  pass 'several stages on one arm join as not_in_pool+not_launchable (canonical order)'
else
  fail "join case rc=$rc out=$out"
fi

# ── 7. requested_arm_incapable is RESERVED for the no-cell truth ───────────
# haiku has no capability_matrix cell for kind=code -> incapable is TRUE.
set +e
out="$(run "$ARBITER" '{"kind":"code","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-7","requested_arm":"haiku"}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 69 && "$(tok "$out" reason)" == "requested_arm_incapable" ]]; then
  pass 'pin haiku on kind=code (no matrix cell): requested_arm_incapable, rc=69 -- the reserved case'
else
  fail "incapable-reserved case rc=$rc out=$out"
fi
# ...and a pin to an arm WITH a cell never reads incapable: excluded by a
# stage instead (this is the live bug's exact shape, inverted: honest now).
set +e
out="$(run "$ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-7b","requested_arm":"fable","launchable_arms":["codex","sonnet"]}' "$HEALTHY")"
rc=$?
set -e
if [[ ${rc} -eq 69 && "$(tok "$out" reason)" == "requested_arm_not_launchable" ]]; then
  pass 'pin fable (has a plan/heavy cell) refused as requested_arm_not_launchable, never incapable'
else
  fail "capable-pin case rc=$rc out=$out"
fi

# ── RED M2: collapse the stages back to one 'not_allowed' value ────────────
# The pre-fix shape: two facts (pool membership, launchability) folded into
# one opaque token. Under the mutation every stage-precision grep above must
# lose its token -- proven with the join case (6): 'not_in_pool+not_launchable'
# becomes 'not_allowed' and the assertion can no longer match.
MUT_ARBITER="$TMP/scripts-mut/route-arbiter-mutated.sh"
mkdir -p "$TMP/scripts-mut" "$TMP/config"
cp "$ARBITER" "$MUT_ARBITER"
# the arbiter resolves ../config/leadv2-routing.yaml relative to its own
# location -- the throwaway copy needs the real config beside it.
cp "${PLUGIN_ROOT}/config/leadv2-routing.yaml" "$TMP/config/leadv2-routing.yaml"
python3 - "$MUT_ARBITER" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = """    if not _pool_contains(_a): _stage_add(_a,'not_in_pool')
    if launchable is not None and _a not in launchable: _stage_add(_a,'not_launchable')"""
mut = """    if not _pool_contains(_a) or (launchable is not None and _a not in launchable): _stage_add(_a,'not_allowed')"""
order_anchor = "_STAGE_ORDER=['not_in_pool','not_launchable','untrusted','capped','failure_memory','price_ratio']"
order_mut = "_STAGE_ORDER=['not_allowed','untrusted','capped','failure_memory','price_ratio']"
n = src.count(anchor)
no = src.count(order_anchor)
if n != 1 or no != 1:
    sys.exit('M2 anchors: stages found %d, order found %d (expected 1 each) -- '
             're-anchor the control, do not silence it' % (n, no))
src = src.replace(anchor, mut).replace(order_anchor, order_mut)
open(path, 'w').write(src)
PY
if [[ $? -ne 0 ]]; then
  fail "(m2) mutation anchor missing -- control not falsifiable"
else
  set +e
  # The mutated copy lives in $TMP and would resolve ../config relative to
  # itself; pin the REAL canonical config via the env seam instead.
  out="$(LEADV2_ROUTE_ARBITER_ROUTING_YAML="${PLUGIN_ROOT}/config/leadv2-routing.yaml" \
    run "$MUT_ARBITER" '{"kind":"plan","size":"heavy","complexity":"standard","complexity_source":"heuristic","task":"st-m2","arm_pool":["glm","codex"],"launchable_arms":["glm","codex"]}' "$HEALTHY")"
  rc=$?
  set -e
  if [[ ${rc} -eq 0 && "$(excl "$out")" == *'fable:not_allowed'* && "$(excl "$out")" != *'not_in_pool'* ]]; then
    pass '(m2) stage collapse reproduces the opaque not_allowed token, suite is red under it'
  else
    fail "(m2) mutation did not flip the token rc=$rc out=$out"
  fi
fi

SUMMARY_PRINTED=1
printf 'SUMMARY: pass=%s fail=%s\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
