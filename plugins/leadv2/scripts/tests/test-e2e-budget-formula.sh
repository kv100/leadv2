#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-product-close
# E2E-GATE-BUDGET-CAP-CONTRADICTS-ITS-OWN-FORMULA-01: the close-run e2e budget
# cap must not truncate the linear formula the same function just computed.
# The old 3600s cap engaged above 21 selected suites, so a 65-suite run
# computed 8880s but was scheduled under 3600s and killed rc=124 at 37/65.
# The cap is a runaway ceiling (10800s) that must engage only above 81 suites.
# Evaluates the live formula + cap lines extracted from the script itself, so
# it goes red if either line drifts.  Point LEADV2_DISPATCH_PRODUCT_CLOSE_FILE
# at a mutated copy for the negative controls.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/.." && pwd)"
SCRIPT="${LEADV2_DISPATCH_PRODUCT_CLOSE_FILE:-${SCRIPTS}/leadv2-dispatch-product-close.sh}"
PASS=0 FAIL=0
ok() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

if [[ ! -f "${SCRIPT}" ]]; then
  printf 'FAIL: script under test missing: %s\n' "${SCRIPT}" >&2
  exit 1
fi

# The two live lines, extracted verbatim from the script (tolerant of the cap
# constant: a value change is judged by the behavior assertions, not text).
FORMULA_LINE="$(grep -E '^[[:space:]]*_pc_e2e_budget_default=\$\(\(.*\)\)[[:space:]]*$' "${SCRIPT}" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
CAP_LINE="$(grep -E '^[[:space:]]*\[\[ "\$\{_pc_e2e_budget_default\}" -gt [0-9]+ \]\] && _pc_e2e_budget_default=[0-9]+[[:space:]]*$' "${SCRIPT}" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
if [[ -z "${FORMULA_LINE}" ]]; then
  bad 'formula line _pc_e2e_budget_default=$(( 1200 + 120 * ... )) not found in script'
fi
if [[ -z "${CAP_LINE}" ]]; then
  bad 'cap line [[ "${_pc_e2e_budget_default}" -gt N ]] && ...=N not found in script'
fi
if [[ ${FAIL} -gt 0 ]]; then
  printf 'test-e2e-budget-formula: %d passed, %d failed\n' "${PASS}" "${FAIL}"
  exit 1
fi

budget_for() { # <selected> -> prints the default budget the script computes
  local selected="$1"
  (
    _pc_e2e_selected_for_budget="${selected}"
    eval "${FORMULA_LINE}"
    eval "${CAP_LINE}"
    printf '%s' "${_pc_e2e_budget_default}"
  )
}

expect_budget() { # <selected> <expected_s> <label>
  local got
  got="$(budget_for "$1")"
  if [[ "${got}" == "$2" ]]; then
    ok "$3 (selected=$1 -> ${got}s)"
  else
    bad "$3: selected=$1 expected ${2}s, got ${got}s"
  fi
}

expect_budget 1    1200  'one-suite floor (1200 base)'
expect_budget 21   3600  'old 21-suite boundary unchanged'
expect_budget 22   3720  'first selection above the old cap is no longer truncated'
expect_budget 65   8880  'REGRESSION: 65 selected gets the formula 8880s, not the old 3600s cap'
expect_budget 81   10800 'last value under the new ceiling computes exactly 10800s'
expect_budget 82   10800 'new ceiling engages only above 81 suites (10920 clamps to 10800)'

# The operator override stays authoritative over the computed budget.
if grep -qF '_pc_e2e_timeout_s="${LEADV2_PHASE8_E2E_TIMEOUT_S:-${_pc_e2e_budget_default}}"' "${SCRIPT}"; then
  ok 'operator override LEADV2_PHASE8_E2E_TIMEOUT_S still precedes the computed budget'
else
  bad 'override seam _pc_e2e_timeout_s="${LEADV2_PHASE8_E2E_TIMEOUT_S:-...}" not found'
fi

# The emitted gate-log formula string must agree with the cap (the ticket is
# that one artifact contradicted its own formula).
if grep -Fq 'min(3600' "${SCRIPT}"; then
  bad 'stale min(3600,...) text still present in script'
else
  ok 'no min(3600,...) text remains'
fi
if grep -Fq 'budget-formula: min(10800,1200+120*(selected-1))' "${SCRIPT}"; then
  ok 'e2e-gate.log budget-formula string matches the raised cap'
else
  bad 'e2e-gate.log budget-formula string does not state min(10800,...)'
fi

printf 'test-e2e-budget-formula: %d passed, %d failed\n' "${PASS}" "${FAIL}"
exit "${FAIL}"
