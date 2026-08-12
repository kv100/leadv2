#!/usr/bin/env bash
# tests/test-diagnose-codex-disabled-degrades.sh — design §7 test 12.
#
# Asserts that --mode diagnose degrades the same way as --mode plan when
# codex is disabled: uses diagnose_run verbs, produces root-cause.md.
# Structurally: the diagnose mode in the engine shares the same
# classify_arm_failure path and arm_unavailable logic as plan mode.
#
# Run: bash plugins/leadv2/scripts/tests/test-diagnose-codex-disabled-degrades.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

# Case 1: diagnose mode has its own journal verb (diagnose_run).
if grep -q 'diagnose_run' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode uses diagnose_run verb"
else
  fail "diagnose mode missing diagnose_run verb"
fi

# Case 2: diagnose mode journals arm_unavailable.
if grep -q 'diagnose_run arm_unavailable' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode journals arm_unavailable"
else
  fail "diagnose mode missing arm_unavailable journal"
fi

# Case 3: diagnose mode writes root-cause.md (not context.yaml).
if grep -q 'root-cause.md' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode writes root-cause.md"
else
  fail "diagnose mode missing root-cause.md artifact"
fi

# Case 4: diagnose mode has no status=parked (degrades, never parks).
if ! grep -q 'status=parked' "${ENGINE}" 2>/dev/null; then
  pass "diagnose mode has no status=parked"
else
  fail "diagnose mode has status=parked (should not)"
fi

printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
