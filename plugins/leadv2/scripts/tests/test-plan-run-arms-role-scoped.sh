#!/usr/bin/env bash
# tests/test-plan-run-arms-role-scoped.sh — design §5 test 6.
#
# Asserts DISPATCHABLE_PLAN_ARMS excludes glm/kimi and includes codex/sonnet,
# read from the resolver via importlib (not a literal in the test). Mirrors the
# importlib pattern from test-arm-ladder-vocabulary-drift.sh:44-51.
#
# Also verifies --plan-pool is wired in the resolver CLI and produces pool
# output filtered against DISPATCHABLE_PLAN_ARMS.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-arms-role-scoped.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOLVER_PY="${SCRIPTS_ROOT}/lib/leadv2-glm-policy-resolve.py"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# ---------------------------------------------------------------------------
# Case 1: DISPATCHABLE_PLAN_ARMS membership (read from resolver, not a literal)
# ---------------------------------------------------------------------------
_plan_arms="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_PLAN_ARMS)))
' "${RESOLVER_PY}" 2>&1)" || { echo "ERROR: cannot import DISPATCHABLE_PLAN_ARMS"; exit 1; }

_t1_ok=1
for _bad in glm kimi; do
  case " ${_plan_arms} " in *" ${_bad} "*) _t1_ok=0 ;; esac
done
for _good in codex sonnet opus fable; do
  case " ${_plan_arms} " in *" ${_good} "*) ;; *) _t1_ok=0 ;; esac
done
if [[ "${_t1_ok}" == "1" ]]; then
  pass "DISPATCHABLE_PLAN_ARMS = {${_plan_arms}} — excludes glm/kimi, includes codex/sonnet/opus/fable"
else
  fail "DISPATCHABLE_PLAN_ARMS = {${_plan_arms}} — wrong membership"
fi

# ---------------------------------------------------------------------------
# Case 2: DISPATCHABLE_BUILD_ARMS is unchanged (regression proof).
# ---------------------------------------------------------------------------
_build_arms="$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("_pr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(" ".join(sorted(m.DISPATCHABLE_BUILD_ARMS)))
' "${RESOLVER_PY}" 2>&1)" || { echo "ERROR: cannot import DISPATCHABLE_BUILD_ARMS"; exit 1; }

if [[ " ${_build_arms} " == *" glm "* && " ${_build_arms} " == *" codex "* && " ${_build_arms} " == *" sonnet "* ]]; then
  pass "DISPATCHABLE_BUILD_ARMS unchanged = {${_build_arms}}"
else
  fail "DISPATCHABLE_BUILD_ARMS = {${_build_arms}} — should still contain glm/codex/sonnet"
fi

# ---------------------------------------------------------------------------
# Case 3: --plan-pool flag exists and filters glm/kimi out of the pool.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/repo/.claude/ref"
cat > "${TMP}/repo/.claude/ref/leadv2-routing.yaml" <<'YAML'
router:
  glm_policy:
    codex_quota_gate:
      review_arm_order: [codex, glm, sonnet, opus]
      review_threshold_pct: 95
      anthropic_review_threshold_pct: 95
YAML

cat > "${TMP}/stub-quota.sh" <<'SH'
#!/usr/bin/env bash
printf '{"status":"ok"}\n'
SH
chmod +x "${TMP}/stub-quota.sh"

_pool_out="$(python3 "${RESOLVER_PY}" \
  --routing-yaml "${TMP}/repo/.claude/ref/leadv2-routing.yaml" \
  --job plan --base-arm codex --plan-pool --signals '{}' \
  --quota-live "${TMP}/stub-quota.sh" 2>/dev/null)"
_pool_line="$(printf '%s\n' "${_pool_out}" | sed -n 's/^pool=//p' | head -1)"

# Pool must NOT contain glm or kimi entries.
if printf '%s' "${_pool_line}" | grep -qE '(^|,)(glm|kimi):'; then
  fail "--plan-pool pool contains glm or kimi: ${_pool_line}"
else
  pass "--plan-pool excludes glm/kimi: ${_pool_line}"
fi

# Pool must be non-empty.
if [[ -n "${_pool_line}" ]]; then
  pass "--plan-pool pool is non-empty"
else
  fail "--plan-pool pool is empty"
fi

# ---------------------------------------------------------------------------
printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
