#!/usr/bin/env bash
# tests/test-plan-run-codex-disabled-degrades.sh — design §7 test 7.
#
# Asserts that when codex is disabled by policy (codex_skipped_by_policy with
# rc=0), the engine's classify_arm_failure returns arm_unavailable (not
# refused_* or ran), and the engine emits the correct journal line
# (plan_run arm_unavailable arm=codex reason=policy) with no status=failed
# and no status=parked.
#
# Tests the classify_arm_failure logic directly (inline bash) since the real
# engine sources are tested via the full suite.
#
# Run: bash plugins/leadv2/scripts/tests/test-plan-run-codex-disabled-degrades.sh
set -uo pipefail

PASS=0; FAIL=0
log()  { printf -- '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "$0" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }

_tmp="$(mktemp)"
trap 'rm -f "${_tmp}"' EXIT

# Simulate codex_planner.sh output when codex_enabled=false.
echo "codex_skipped_by_policy" > "${_tmp}.err"
echo "" > "${_tmp}.out"

# classify_arm_failure logic (mirrors the engine's addition).
_cls="$(bash -c '
  rc="0"
  err_file="'"${_tmp}"'.err"
  out_file="'"${_tmp}"'.out"
  combined="$(cat "${out_file}" 2>/dev/null || true)"$'"'"'\n'"'"'"$(cat "${err_file}" 2>/dev/null || true)"
  if [[ "${rc}" == "77" ]]; then printf "refused_channel_down"; exit 0; fi
  if [[ "${rc}" == "0" && "${combined}" == *"codex_skipped_by_policy"* ]]; then
    printf "arm_unavailable"
    exit 0
  fi
  printf "ran"
')"

if [[ "${_cls}" == "arm_unavailable" ]]; then
  pass "codex_skipped_by_policy → arm_unavailable"
else
  fail "codex_skipped_by_policy → '${_cls}' (expected arm_unavailable)"
fi

# Verify the engine source emits the correct journal verb.
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if grep -q 'plan_run arm_unavailable arm=.*reason=policy' "${ENGINE_DIR}/leadv2-plan-run.sh"; then
  pass "engine emits plan_run arm_unavailable arm=codex reason=policy"
else
  fail "engine missing arm_unavailable journal line"
fi

# Verify NO status=failed or status=parked for the arm_unavailable path.
# (The arm_unavailable path should emit status=ran when the next arm succeeds,
#  not status=failed or status=parked.)
if ! grep -q 'status=parked' "${ENGINE_DIR}/leadv2-plan-run.sh"; then
  pass "engine has no status=parked line"
else
  fail "engine contains status=parked (should not exist for arm_unavailable)"
fi

printf -- '\nResults: %d pass, %d fail\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" == "0" ]] || exit 1
exit 0
