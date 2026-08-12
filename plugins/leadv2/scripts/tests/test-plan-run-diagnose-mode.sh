#!/usr/bin/env bash
# tests/test-plan-run-diagnose-mode.sh — design §5 tests 10, 12.
#
# Test 10: --mode diagnose prompt contains no persona-engine constants
#          (no journalctl -u persona-engine, no persona_engine table names).
# Test 12: diagnose degrade proof with diagnose_run verbs — the engine journals
#          arm_unavailable in diagnose mode just as in plan mode, and
#          root-cause.md is the output artifact.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-diagnose-mode.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-plan-run.sh"

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
bash -n "${ENGINE}" 2>/dev/null || { echo "ERROR: engine syntax check failed"; exit 1; }

# ---------------------------------------------------------------------------
# Test 10: engine contains no persona-engine constants (portable across repos)
# ---------------------------------------------------------------------------
log "Test 10: diagnose mode has no persona-engine constants"
if grep -q 'journalctl.*persona-engine' "${ENGINE}" || grep -q 'persona_engine' "${ENGINE}"; then
  fail "engine contains persona-engine constants (should be portable)"
else
  pass "engine has no persona-engine constants"
fi

# Also verify --log-path and --diff-paths are accepted as flags.
if grep -q '\-\-log-path' "${ENGINE}" && grep -q '\-\-diff-paths' "${ENGINE}"; then
  pass "engine accepts --log-path and --diff-paths flags"
else
  fail "engine missing --log-path or --diff-paths flag"
fi

# ---------------------------------------------------------------------------
# Test 12: diagnose mode uses diagnose_run verbs and arm_unavailable path
# ---------------------------------------------------------------------------
log "Test 12: diagnose mode journals arm_unavailable and writes root-cause.md"

# Verify the engine source contains diagnose_run journal verbs.
if grep -q 'diagnose_run arm_unavailable' "${ENGINE}"; then
  pass "engine journals diagnose_run arm_unavailable"
else
  fail "engine missing diagnose_run arm_unavailable journal"
fi

# Verify the gate artifact for diagnose is root-cause.md (not context.yaml).
if grep -q 'root-cause.md' "${ENGINE}"; then
  pass "diagnose gate artifact is root-cause.md"
else
  fail "diagnose gate missing root-cause.md artifact"
fi

# Verify diagnose gate has acceptance: skipped.
if grep -q 'acceptance:.*skipped' "${ENGINE}" || grep -q '"skipped"' "${ENGINE}" || grep -q "'skipped'" "${ENGINE}"; then
  pass "diagnose gate carries acceptance: skipped"
else
  fail "diagnose gate missing acceptance: skipped field"
fi

# Verify diagnose uses exit code 9 for blocked (not 4 or 1).
# Find diagnose-specific blocked exits by looking for the pattern after
# diagnose_run status=blocked.
_diag_blocked_exits="$(grep -A2 'diagnose_run.*status=blocked' "${ENGINE}" | grep -oE 'exit [0-9]+' | sort -u)"
if printf '%s' "${_diag_blocked_exits}" | grep -q 'exit 9'; then
  pass "diagnose blocked exits with code 9"
else
  fail "diagnose blocked exit code wrong: '${_diag_blocked_exits}' (expected 9)"
fi

# ---------------------------------------------------------------------------
printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
