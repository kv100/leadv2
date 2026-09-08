#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, discovered by scan_suite_triggers):
# run-all-triggers: run-all leadv2-phase8-e2e-gate
# plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh — GATE-BUDGET-TOO-SMALL-FOR-run-all-OWN-SUITES-01
#
# Measured 2026-09-08 on parked lane fb9df7f1 (worktree d2823c51e670, base
# main@3cb4c49f): run-all --scope changed selects 6 suites first-run / 4 steady
# and finishes in ~165s against a 900s budget — scoped, and not slow. What the
# gate could not do was ACCOUNT for its budget: a timeout verdict said nothing
# about elapsed time, so diagnosing one took a 510-line log. This suite pins
# the contract the fix added: EVERY verdict (pass / fail / timeout) carries
# elapsed_s and budget_s, and the gate still reaches real verdicts in both
# directions — a broken lane must still produce verdict=fail.
#
# Assertions are on VALUES (exit codes, sentinel presence, executed-suite
# counts, numeric elapsed/budget fields) — never on human-readable log prose.
#
# DECLARED NEGATIVE CONTROLS (E2E-KILLRATE-01), applied by
# leadv2-mutation-control.sh to lines INSIDE the two gate function bodies
# (never top level). Both must turn THIS suite red:
#   M1 elapsed-mut-1 — force the span to zero:
#     leadv2-mutation-control.sh plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh \
#       plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh \
#       's/_p8_e2e_stop_s - _p8_e2e_start_s/_p8_e2e_start_s - _p8_e2e_start_s/'
#     -> P-case journal says elapsed_s=0 for a stub that slept 2s: red on the
#        ELAPSED VALUE (0 < 2).
#   M2 skip-mut-1 — reach pass by running nothing (anchored to the invocation
#     line inside _p8_run_e2e_sweep's body, so the mutant touches no other
#     line):
#     leadv2-mutation-control.sh plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh \
#       plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh \
#       's|^  ( cd .*_lv2_selfcheck_timeout_run.*$|  true # skip-mut-1: sweep skipped|'
#     -> gate exits 0 / verdict=pass having executed ZERO suites: red on the
#        EXECUTED-SUITE COUNT (0 != 1). A gate that passes by running less
#        than it should is the defect this family removed three times.
#
# Portable: bash 3.2, no GNU-only tools, scratch fixtures only (never the
# live repo). Run: bash plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

GATE_SH="${SCRIPTS_ROOT}/leadv2-phase8-e2e-gate.sh"

PASS=0; FAIL=0; NOTRUN=0; ERRORS=()
log()    { printf -- '[TEST] %s\n' "$*"; }
pass()   { PASS=$((PASS + 1)); log "PASS: $1"; }
fail()   { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }
notrun() { NOTRUN=$((NOTRUN + 1)); log "NOT RUN: $1"; }

if bash -n "$GATE_SH"; then
  pass "bash -n clean (leadv2-phase8-e2e-gate.sh)"
else
  fail "bash -n failed on leadv2-phase8-e2e-gate.sh"
fi

# ── fixture builder (same shape as test-e2e-timeout-classification.sh) ───────
# One committed file + a dirty working-tree edit, so the lane diff is real and
# non-docs-only; the stub e2e command's behaviour is chosen per case below.
build_fixture() { # <root> <e2e_body_file>
  local root="$1" e2e_body_file="$2"
  mkdir -p "${root}"
  git -C "${root}" init -q
  git -C "${root}" config user.email test@test.local
  git -C "${root}" config user.name test
  printf 'A-fixed\n' > "${root}/A.txt"
  cp "${e2e_body_file}" "${root}/fake-e2e.sh"
  chmod +x "${root}/fake-e2e.sh"
  git -C "${root}" add -A
  git -C "${root}" commit -q -m "fixture: fixed A"
  printf 'A-dirty\n' > "${root}/A.txt"
}

# run_gate <root> <sig> <timeout_s> -> sets RC, MD, FLAG, JOURNAL, GLOG
run_gate() {
  local root="$1" sig="$2" timeout_s="$3"
  local handoff="${root}/docs/handoff/${sig}"
  mkdir -p "${handoff}"
  JOURNAL="${TMP}/journal-${sig}.log"; : > "${JOURNAL}"
  local stub_journal="${TMP}/stub-journal-${sig}.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "${stub_journal}"
  printf 'printf '\''%%s\\n'\'' "$*" >> %q\n' "${JOURNAL}" >> "${stub_journal}"
  chmod +x "${stub_journal}"
  RC=0
  CLAUDE_PROJECT_ROOT="${root}" \
  LEADV2_PROJECT_ROOT="${root}" \
  LEADV2_HANDOFF_DIR="${root}/docs/handoff" \
  LEADV2_E2E_CMD="bash ${root}/fake-e2e.sh" \
  LEADV2_PHASE8_E2E_TIMEOUT_S="${timeout_s}" \
  LEADV2_E2E_OWNERSHIP=0 \
  LEADV2_LANE_WORK_ROOT="${root}" \
  LEADV2_JOURNAL_BIN="${stub_journal}" \
    bash "$GATE_SH" "${sig}" >/dev/null 2>&1 || RC=$?
  MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
  GLOG="$(cat "${handoff}/e2e-gate.log" 2>/dev/null || true)"
}

# journal_kv <sig> <verdict> <key> -> numeric value of key on that verdict's
# decision line, or the empty string when the line is missing. Each fixture
# journal carries exactly one verdict decision, so a plain sed suffices (no
# pipe, no head — see abf5dbae for the SIGPIPE/pipefail race this avoids).
# BSD sed has no \b: keys are matched with a mandatory leading space.
journal_kv() { # <sig> <verdict> <key>
  sed -n "s/.*e2e_gate task=[^ ]* status=ran verdict=$2 .*[ ]$3=\([0-9][0-9]*\).*/\1/p" \
    "${TMP}/journal-$1.log"
}

# executed_suite_count <glog> -> how many suites the sweep actually ran.
executed_suite_count() { # <glog-text>
  grep -c '^\[RUN\] ' <<< "$1" || true
}

TMP="$(lv2_mktemp_dir "gate-reaches-a-verdict-test")"; trap 'rm -rf "$TMP"' EXIT

STUB_PASS="${TMP}/fake-e2e-pass.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# Sleeps 2s so the elapsed_s floor assertion has teeth.' \
  'echo "[RUN] fake-suite-one"' \
  'sleep 2' \
  'echo "run-all: 1 passed, 0 failed, scope=changed"' \
  'exit 0' > "${STUB_PASS}"
chmod +x "${STUB_PASS}"

STUB_FAIL="${TMP}/fake-e2e-fail.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# Deliberately BROKEN lane fixture: a real, immediate failure.' \
  'echo "[RUN] fake-suite-one"' \
  'echo "  Failures (blocking):"' \
  'echo "    - tests/fake/test-A.sh"' \
  'exit 1' > "${STUB_FAIL}"
chmod +x "${STUB_FAIL}"

STUB_SLEEP="${TMP}/fake-e2e-sleep.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  '# Outlives the 1s budget the T case gives the gate.' \
  'sleep 30' \
  'exit 0' > "${STUB_SLEEP}"
chmod +x "${STUB_SLEEP}"

# ── P: green sweep -> verdict=pass with budget accounting ────────────────────
P_ROOT="${TMP}/p"; build_fixture "${P_ROOT}" "${STUB_PASS}"
lv2_assert_scratch_repo "${P_ROOT}"
run_gate "${P_ROOT}" "psig0001" "60"

P_ELAPSED="$(journal_kv psig0001 pass elapsed_s)"
P_BUDGET="$(journal_kv psig0001 pass budget_s)"
P_COUNT="$(executed_suite_count "${GLOG}")"

if [[ "${RC}" -eq 0 && -n "${FLAG}" ]]; then
  pass "P: green sweep reaches verdict=pass, sentinel written (rc=0)"
else
  fail "P: expected rc=0 + sentinel, got rc=${RC} flag=<${FLAG:-}>"
fi
# Count BEFORE elapsed: the count is skip-mut-1's designated red (a skipped
# sweep legitimately reports elapsed_s=0, so the elapsed check alone would
# redden the skip mutant for the wrong reason).
if [[ "${P_COUNT}" -eq 1 ]]; then
  pass "P: sweep executed exactly 1 suite (count=${P_COUNT})"
else
  fail "P: executed-suite count must be 1, got ${P_COUNT} log=<${GLOG}>"
fi
if [[ "${P_ELAPSED}" =~ ^[0-9]+$ ]] && (( P_ELAPSED >= 2 )); then
  pass "P: verdict=pass reports elapsed_s=${P_ELAPSED} (>= 2s stub floor)"
else
  fail "P: elapsed_s must be >=2 for a 2s sweep, got '${P_ELAPSED:-<no verdict=pass line>}' journal=<$(cat "${TMP}/journal-psig0001.log")>"
fi
if [[ "${P_BUDGET}" == "60" ]]; then
  pass "P: verdict=pass reports budget_s=60 (the configured ceiling)"
else
  fail "P: budget_s must equal the configured 60, got '${P_BUDGET:-<missing>}'"
fi
if [[ "$(sed -n 's/^e2e_gate task=psig0001 verdict=pass elapsed_s=\([0-9]*\) budget_s=\([0-9]*\)$/ok \1 \2/p' <<< "${GLOG}")" == "ok ${P_ELAPSED} 60" ]]; then
  pass "P: gate log ends with the one-line budget accounting"
else
  fail "P: gate log missing one-line 'e2e_gate ... verdict=pass elapsed_s=.. budget_s=..' accounting, tail=<$(tail -3 <<< "${GLOG}")>"
fi

# ── F: broken lane -> verdict=fail, no sentinel, accounting present ──────────
F_ROOT="${TMP}/f"; build_fixture "${F_ROOT}" "${STUB_FAIL}"
lv2_assert_scratch_repo "${F_ROOT}"
run_gate "${F_ROOT}" "fsig0001" "60"

F_ELAPSED="$(journal_kv fsig0001 fail elapsed_s)"
F_BUDGET="$(journal_kv fsig0001 fail budget_s)"
F_COUNT="$(executed_suite_count "${GLOG}")"

if [[ "${RC}" -eq 1 && -z "${FLAG}" ]]; then
  pass "F (negative control): broken lane still reaches verdict=fail, exit 1, no sentinel"
else
  fail "F: expected rc=1 + no sentinel, got rc=${RC} flag=<${FLAG:-}>"
fi
if [[ "${F_ELAPSED}" =~ ^[0-9]+$ ]]; then
  pass "F: verdict=fail carries numeric elapsed_s=${F_ELAPSED}"
else
  fail "F: verdict=fail missing numeric elapsed_s journal=<$(cat "${TMP}/journal-fsig0001.log")>"
fi
if [[ "${F_BUDGET}" == "60" && "${F_COUNT}" -eq 1 ]]; then
  pass "F: budget_s=60 recorded and 1 suite executed before the fail"
else
  fail "F: expected budget_s=60 + count=1, got budget=<${F_BUDGET:-<missing>}> count=${F_COUNT}"
fi

# ── T: sweep outlives budget -> verdict=timeout WITH budget accounting ───────
T_ROOT="${TMP}/t"; build_fixture "${T_ROOT}" "${STUB_SLEEP}"
lv2_assert_scratch_repo "${T_ROOT}"
run_gate "${T_ROOT}" "tsig0001" "1"

T_ELAPSED="$(journal_kv tsig0001 timeout elapsed_s)"
T_BUDGET="$(journal_kv tsig0001 timeout budget_s)"

if [[ "${RC}" -eq 5 && -z "${FLAG}" ]]; then
  pass "T: an over-budget sweep is verdict=timeout exit 5, no sentinel — never a silent pass"
else
  fail "T: expected rc=5 + no sentinel, got rc=${RC} flag=<${FLAG:-}>"
fi
if [[ "${T_ELAPSED}" =~ ^[0-9]+$ ]] && (( T_ELAPSED >= 1 && T_ELAPSED <= 5 )); then
  pass "T: verdict=timeout reports elapsed_s=${T_ELAPSED} (killed at the 1s budget)"
else
  fail "T: elapsed_s must be 1..5 for a 1s-budget kill, got '${T_ELAPSED:-<missing>}' journal=<$(cat "${TMP}/journal-tsig0001.log")>"
fi
if [[ "${T_BUDGET}" == "1" ]] && grep -q '^elapsed_s: [0-9]*$' <<< "${MD}" && grep -q '^budget_s: 1$' <<< "${MD}"; then
  pass "T: budget_s=1 in journal and elapsed_s:/budget_s: in e2e-gate.md — diagnosable from one line"
else
  fail "T: budget accounting incomplete md=<${MD}> budget=<${T_BUDGET:-<missing>}>"
fi

printf -- '\n[TEST] %d passed, %d failed, %d not run\n' "$PASS" "$FAIL" "$NOTRUN"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
