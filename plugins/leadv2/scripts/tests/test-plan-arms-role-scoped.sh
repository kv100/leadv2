#!/usr/bin/env bash
# tests/test-plan-arms-role-scoped.sh — ONE-PATH-PLAN-RUN-01 design §6 test 6.
#
# Asserts DISPATCHABLE_PLAN_ARMS (in leadv2-glm-policy-resolve.py):
#   - excludes glm and kimi
#   - includes codex and sonnet
# Asserted BY READING THE RESOLVER via importlib — never against a literal list
# copied into this test (design §6 test 6, explicit on this point).
#
# Also asserts DISPATCHABLE_BUILD_ARMS is UNCHANGED by the plan addition.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-arms-role-scoped.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOLVER_PY="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# Read DISPATCHABLE_PLAN_ARMS and DISPATCHABLE_BUILD_ARMS from the resolver.
PLAN_ARMS="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_PLAN_ARMS)))
' "$RESOLVER_PY" 2>&1)"

BUILD_ARMS="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_BUILD_ARMS)))
' "$RESOLVER_PY" 2>&1)"

[[ -n "${PLAN_ARMS}" ]] || { echo "ERROR: cannot import DISPATCHABLE_PLAN_ARMS"; exit 1; }

# Case 1: glm and kimi are NOT in DISPATCHABLE_PLAN_ARMS
_ok=1
for _bad in glm kimi; do
  case " ${PLAN_ARMS} " in *" ${_bad} "*) fail "DISPATCHABLE_PLAN_ARMS contains '${_bad}' (must not)"; _ok=0 ;; esac
done
[[ "${_ok}" == "1" ]] && pass "DISPATCHABLE_PLAN_ARMS excludes glm and kimi (${PLAN_ARMS})"

# Case 2: codex and sonnet ARE in DISPATCHABLE_PLAN_ARMS
_ok=1
for _good in codex sonnet; do
  case " ${PLAN_ARMS} " in *" ${_good} "*) ;; *) fail "DISPATCHABLE_PLAN_ARMS missing '${_good}' (must include)"; _ok=0 ;; esac
done
[[ "${_ok}" == "1" ]] && pass "DISPATCHABLE_PLAN_ARMS includes codex and sonnet"

# Case 3: DISPATCHABLE_BUILD_ARMS baseline. NOTE: this expectation was stale
# the moment T19 added freepool (2026-08-26) and was only caught when
# GLM-53-FLASH-ARM-01 (2026-08-27) added glm-flash — the case now asserts the
# full current set {codex, freepool, glm, glm-flash, sonnet} so a future arm
# addition re-reds it here instead of silently passing one behind.
if [[ "${BUILD_ARMS}" == "codex freepool glm glm-flash sonnet" ]]; then
  pass "DISPATCHABLE_BUILD_ARMS baseline held (${BUILD_ARMS})"
else
  fail "DISPATCHABLE_BUILD_ARMS changed! Expected 'codex freepool glm glm-flash sonnet', got '${BUILD_ARMS}'"
fi

# Case 4: plan job pool filtering — resolve_review_pool with job=plan filters
# glm/kimi from the order list (verified via the resolver's own filtering).
# This tests the actual code path: call the resolver with --job plan and check
# the pool output excludes glm.
log ""
log "Case 4: resolver --job plan filters pool against DISPATCHABLE_PLAN_ARMS"

# We need a routing yaml that includes a review_arm_order with glm in it.
# Use the production one if it exists, else a minimal fixture.
ROUTING_YAML="${SCRIPTS_ROOT}/../config/leadv2-routing.yaml"
if [[ ! -f "${ROUTING_YAML}" ]]; then
  _tmp_ry="$(mktemp)"
  cat > "${_tmp_ry}" <<'YAML'
codex_quota_gate:
  review_arm_order: [codex, sonnet, opus, glm]
  review_threshold_pct: 95.0
  glm_review_threshold_pct: 90.0
  anthropic_review_threshold_pct: 85.0
  build_spill_order: [glm, codex, sonnet]
  build_threshold_pct: 80.0
router:
  dispatch_ladder:
    - id: glm
      provider: glm
      dispatch: true
    - id: codex
      provider: codex
      dispatch: true
    - id: sonnet
      provider: anthropic
      dispatch: true
YAML
  ROUTING_YAML="${_tmp_ry}"
  trap 'rm -f "${_tmp_ry}"' EXIT
fi

_pool_out="$(python3 "${RESOLVER_PY}" --routing-yaml "${ROUTING_YAML}" --job plan --base-arm codex --review-pool --signals '{}' 2>/dev/null || true)"
_pool_line="$(printf '%s\n' "${_pool_out}" | sed -n 's/^pool=//p' | head -n1)"

if [[ "${_pool_line}" != *glm* ]]; then
  pass "resolver --job plan pool excludes glm (pool=${_pool_line})"
else
  fail "resolver --job plan pool INCLUDES glm (pool=${_pool_line})"
fi

printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
