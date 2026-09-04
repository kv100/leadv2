#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-dispatch-product-close.sh leadv2-phase8-e2e-gate.sh
# tests/test-e2e-timeout-classification.sh — E2E-TIMEOUT-REPORTED-AS-REGRESSION-01
#
# rc=124 is timeout(1)'s (or the portable fallback watcher's) exit code for a
# command the gate had to kill because it did not finish inside its budget --
# it is not a test failure. Before this fix, leadv2-dispatch-product-close.sh
# fell through the same `else` branch as a real red suite and wrote
# reason=e2e_regression / terminal=dead, killing the lane and discarding a
# round whose own selfcheck had already passed (measured 2026-09-03, lane
# SAFETY-PIN-SECOND-DOOR-01 dispatch 49c6e0c8 -- see
# docs/handoff/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/brief.md).
#
# Negative control, both directions (brief item 5):
#   R1 — a gate command that exits 124 (simulated via a short timeout budget
#        and a fake e2e entrypoint that outlives it) must classify as
#        terminal=parked cause=e2e_timeout, exit 5, and the lane's uncommitted
#        write survives as a checkpoint commit (pc_stop_gate_autocommit runs
#        BEFORE the e2e gate, unconditionally of its verdict).
#   R2 — a real failing suite (rc=1, no timeout involved) must still classify
#        as terminal=dead cause=e2e_regression, exit 8 -- proving this fix did
#        not soften genuine regression handling.
#
# Drives the REAL leadv2-dispatch-product-close.sh (never a reimplementation
# of its gate logic). Portable: no GNU-only date/sed/timeout(1). Never git
# stash/reset --hard/clean.
# Run: bash scripts/tests/test-e2e-timeout-classification.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
PHASE8_GATE_SH="${SCRIPTS_ROOT}/leadv2-phase8-e2e-gate.sh"

PASS=0; FAIL=0; NOTRUN=0; ERRORS=()
log()    { printf -- '[TEST] %s\n' "$*"; }
pass()   { PASS=$((PASS + 1)); log "PASS: $1"; }
fail()   { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }
notrun() { NOTRUN=$((NOTRUN + 1)); log "NOT RUN: $1"; }

if bash -n "$PRODUCT_CLOSE_SH"; then
  pass "bash -n clean (leadv2-dispatch-product-close.sh)"
else
  fail "bash -n failed on leadv2-dispatch-product-close.sh"
fi

# ── fixture builder ──────────────────────────────────────────────────────────
# A single-file fixture: A.txt is committed as "A-fixed", then the working
# tree is mutated so the gate has a real, non-empty in-scope diff to
# checkpoint. fake-e2e.sh's behaviour is passed in by the caller (sleep past
# the budget for R1, or a real failing check for R2).
build_fixture() { # <root> <a_working> <e2e_body_file>
  local root="$1" a_working="$2" e2e_body_file="$3"
  mkdir -p "${root}"
  git -C "${root}" init -q
  git -C "${root}" config user.email test@test.local
  git -C "${root}" config user.name test

  printf 'A-fixed\n' > "${root}/A.txt"
  cp "${e2e_body_file}" "${root}/fake-e2e.sh"
  chmod +x "${root}/fake-e2e.sh"
  git -C "${root}" add -A
  git -C "${root}" commit -q -m "fixture: fixed A"

  printf '%s\n' "${a_working}" > "${root}/A.txt"
}

TMP="$(lv2_mktemp_dir "e2e-timeout-classification-test")"; trap 'rm -rf "$TMP"' EXIT

SLEEPER="${TMP}/fake-e2e-sleep.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# Ignores --scope/etc, outlives any sane timeout budget for this test.' \
  'sleep 30' \
  'exit 0' > "${SLEEPER}"
chmod +x "${SLEEPER}"

REDSUITE="${TMP}/fake-e2e-fail.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# A real, immediate failure -- no timeout involved.' \
  'echo "  Failures (blocking):"' \
  'echo "    - tests/unit/test-A.sh"' \
  'exit 1' > "${REDSUITE}"
chmod +x "${REDSUITE}"

# ── gate runner ───────────────────────────────────────────────────────────────
run_gate() { # <root> <sig8> <e2e_cmd> <timeout_s> <ledger_bin> -> sets RC, MD, FLAG, JOURNAL_LOG
  local root="$1" sig8="$2" e2e_cmd="$3" timeout_s="$4" ledger_bin="$5"
  local handoff="${root}/docs/handoff/dispatch-${sig8}"
  rm -rf "${handoff}"
  JOURNAL_LOG="${TMP}/journal-${sig8}.log"; : > "${JOURNAL_LOG}"
  local stub_journal="${TMP}/stub-journal-${sig8}.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "${stub_journal}"
  printf 'printf '\''%%s\\n'\'' "$*" >> %q\n' "${JOURNAL_LOG}" >> "${stub_journal}"
  chmod +x "${stub_journal}"

  RC=0
  LEADV2_E2E_CMD="${e2e_cmd}" \
  LEADV2_PHASE8_E2E_TIMEOUT_S="${timeout_s}" \
  LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_DISPATCH_LANE_WRITES="A.txt" \
  LEADV2_LANE_WORK_ROOT="${root}" \
  LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
  LEADV2_DISPATCH_TERMINAL_LEDGER=1 \
  LEADV2_DISPATCH_LEDGER_BIN="${ledger_bin}" \
  LEADV2_JOURNAL_BIN="${stub_journal}" \
    bash "$PRODUCT_CLOSE_SH" "${root}" "${sig8}" codex "" 1 0 "" >/dev/null 2>&1 || RC=$?
  MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
}

run_phase8_gate() { # <root> <sig8> <timeout_s> <journal_bin>
  local root="$1" sig8="$2" timeout_s="$3" journal_bin="$4"
  local handoff="${root}/docs/handoff/${sig8}"
  mkdir -p "${handoff}"
  P8_RC=0
  P8_LOG="${TMP}/phase8-${sig8}.log"
  CLAUDE_PROJECT_ROOT="${root}" \
  LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_HANDOFF_DIR="${root}/docs/handoff" \
  LEADV2_E2E_CMD="bash ${root}/fake-e2e.sh" \
  LEADV2_PHASE8_E2E_TIMEOUT_S="${timeout_s}" \
  LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_LANE_WORK_ROOT="${root}" \
  LEADV2_JOURNAL_BIN="${journal_bin}" \
    bash "${PHASE8_GATE_SH}" "${sig8}" >"${P8_LOG}" 2>&1 || P8_RC=$?
  P8_MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  P8_FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
  P8_JOURNAL="$(cat "${TMP}/journal-${sig8}.log" 2>/dev/null || true)"
}

LEDGER_LOG="${TMP}/ledger-calls.log"; : > "${LEDGER_LOG}"
STUB_LEDGER="${TMP}/stub-ledger.sh"
printf '%s\n' '#!/usr/bin/env bash' > "${STUB_LEDGER}"
printf 'printf '\''%%s\\n'\'' "$*" >> %q\n' "${LEDGER_LOG}" >> "${STUB_LEDGER}"
printf '%s\n' 'exit 0' >> "${STUB_LEDGER}"
chmod +x "${STUB_LEDGER}"

# ── R1: sweep outlives its budget -> timeout, not regression ────────────────
R1="${TMP}/r1"; mkdir -p "${R1}"
build_fixture "${R1}" "A-changed" "${SLEEPER}"
lv2_assert_scratch_repo "${R1}"

run_gate "${R1}" "r1sig001" "bash ${R1}/fake-e2e.sh" "1" "${STUB_LEDGER}"

if [[ "${RC}" -eq 5 ]] && grep -q 'status: unknown' <<<"${MD}" && grep -q 'reason: e2e_timeout' <<<"${MD}"; then
  pass "R1: rc=124 classifies as status:unknown reason:e2e_timeout, exit 5 (not 8/e2e_regression)"
else
  fail "R1: expected exit 5 + status:unknown + reason:e2e_timeout, got rc=${RC} md=<${MD}>"
fi

if grep -qE 'e2e_gate task=r1sig001 status=ran verdict=timeout rc=124' "${JOURNAL_LOG}"; then
  pass "R1: journal records verdict=timeout rc=124"
else
  fail "R1: journal missing verdict=timeout line -- $(cat "${JOURNAL_LOG}")"
fi

if grep -qE '^write-terminal r1sig001 .*parked e2e_timeout' "${LEDGER_LOG}"; then
  pass "R1: ledger terminal is parked/e2e_timeout, not dead/e2e_regression"
else
  fail "R1: ledger call did not record parked/e2e_timeout -- $(cat "${LEDGER_LOG}")"
fi

# work-survives: pc_stop_gate_autocommit runs before the e2e gate regardless
# of its verdict -- the lane's in-scope write must be checkpointed, not left
# to rot as an uncommitted diff a later `dead` sweep could discard.
r1_log="$(git -C "${R1}" log --oneline 2>/dev/null || true)"
if grep -q 'STOP-GATE' <<<"${r1_log}"; then
  pass "R1: worker's write survives as a checkpoint commit despite the timeout terminal"
else
  fail "R1: no checkpoint commit found after timeout -- log=<${r1_log}>"
fi

# ── R2: negative control -- a REAL failing suite still kills the lane ───────
R2="${TMP}/r2"; mkdir -p "${R2}"
build_fixture "${R2}" "A-changed" "${REDSUITE}"
lv2_assert_scratch_repo "${R2}"

run_gate "${R2}" "r2sig001" "bash ${R2}/fake-e2e.sh" "900" "${STUB_LEDGER}"

if [[ "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}"; then
  pass "R2 (negative control): a real rc=1 failure still classifies as e2e_regression, exit 8"
else
  fail "R2 (negative control): expected exit 8 + e2e_regression, got rc=${RC} md=<${MD}>"
fi

if grep -qE '^write-terminal r2sig001 .*dead e2e_regression' "${LEDGER_LOG}"; then
  pass "R2: ledger terminal is still dead/e2e_regression for a genuine failure"
else
  fail "R2: ledger call did not record dead/e2e_regression -- $(cat "${LEDGER_LOG}")"
fi

# ── R3: standalone phase-8 gate records the same timeout as unknown ─────────
R3="${TMP}/r3"; mkdir -p "${R3}"
build_fixture "${R3}" "A-changed" "${SLEEPER}"
lv2_assert_scratch_repo "${R3}"
R3_JOURNAL="${TMP}/journal-r3sig001.log"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' \"\$*\" >> \"${R3_JOURNAL}\"" > "${TMP}/stub-journal-r3.sh"
chmod +x "${TMP}/stub-journal-r3.sh"
run_phase8_gate "${R3}" "r3sig001" "1" "${TMP}/stub-journal-r3.sh"

if [[ "${P8_RC}" -eq 1 ]] && grep -q 'status: unknown' <<<"${P8_MD}" \
   && grep -q 'reason: e2e_timeout' <<<"${P8_MD}" && [[ -z "${P8_FLAG}" ]]; then
  pass "R3: standalone phase-8 gate records timeout as unknown and writes no pass sentinel"
else
  fail "R3: expected rc 1 + unknown timeout + no sentinel, got rc=${P8_RC} md=<${P8_MD}> flag=<${P8_FLAG}> log=<$(cat "${P8_LOG}")>"
fi

if grep -qE 'e2e_gate task=r3sig001 status=ran verdict=timeout rc=124' <<<"${P8_JOURNAL}"; then
  pass "R3: standalone phase-8 journal records verdict=timeout rc=124"
else
  fail "R3: standalone phase-8 journal missing timeout line -- ${P8_JOURNAL} log=<$(cat "${P8_LOG}")>"
fi

printf -- '\n[TEST] %d passed, %d failed, %d not run\n' "$PASS" "$FAIL" "$NOTRUN"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
