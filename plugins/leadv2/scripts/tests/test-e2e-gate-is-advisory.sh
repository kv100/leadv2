#!/usr/bin/env bash
# tests/test-e2e-gate-is-advisory.sh — E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01
# (founder decision, 2026-09-17) guard suite.
#
# Pins the terminal effect of the failing e2e branch in
# leadv2-dispatch-product-close.sh (the `else` arm of the ownership
# classification, after the pre_existing_red/foreign arm): a red e2e verdict is
# REPORTED — e2e-gate.md keeps `status: fail / reason: e2e_regression` with the
# failing-suite names, the gate run is journalled, an advisory decision line is
# emitted — and the lane does NOT die there. No `dead` terminal, no exit 8; the
# lane falls through to the review gate, which remains the judge and keeps its
# kill. The E2E_ON!=1 kill-switch branch is a different state (deliberately
# disabled) and keeps its own meaning; e2e_timeout is a separate row.
#
# Supersedes the wave2 finding 6 behaviour pinned by the pre-2026-09-17
# assertions in test-e2e-timeout-classification.sh (R2), test-e2e-foreign-
# failure.sh (R1-R4) and test-e2e-gate-lane-root.sh (case b) — those now assert
# the advisory fall-through per the recorded decision in the script comment
# ("E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01").
#
# Drives the REAL leadv2-dispatch-product-close.sh (never a reimplementation of
# its gate logic). Portable: no GNU-only date/sed/timeout(1), no Bash-4-only
# features. Never git stash/reset --hard/clean.
# Run: bash scripts/tests/test-e2e-gate-is-advisory.sh
# Exit 0 = all pass; non-zero = failures found.
# run-all-triggers: leadv2-dispatch-product-close
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"

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

# The branch under test must still carry the advisory marker and must NOT have
# regrown the terminal it lost (a mutation control that silently rots into a
# permanent green is worse than no control).
if grep -q 'E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01' "$PRODUCT_CLOSE_SH" \
   && grep -q 'status=advisory rc=' "$PRODUCT_CLOSE_SH"; then
  pass "advisory branch present in product-close (decision marker + advisory emit)"
else
  fail "advisory branch NOT found in product-close — decision comment or emit line missing"
fi

# ── fixture builder ──────────────────────────────────────────────────────────
# Same shape as test-e2e-foreign-failure.sh: tests/unit/test-A.sh fails iff
# A.txt == "broken-A"; fake-e2e.sh mirrors run-all's "Failures (blocking):"
# block so _failing_suites_csv is exercised from the log parse too.
build_fixture() { # <root> <a_working>
  local root="$1" a_working="$2"
  mkdir -p "${root}/tests/unit"
  git -C "${root}" init -q
  git -C "${root}" config user.email test@test.local
  git -C "${root}" config user.name test

  printf 'A-fixed\n' > "${root}/A.txt"
  cat > "${root}/tests/unit/test-A.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
content="$(cat A.txt 2>/dev/null || true)"
[[ "${content}" != "broken-A" ]]
EOF
  chmod +x "${root}/tests/unit/test-A.sh"
  cat > "${root}/fake-e2e.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
failed=0
for f in tests/unit/*.sh; do
  [[ -f "${f}" ]] || continue
  ( env RUN_MODE=dry_run bash "${f}" ) >/dev/null 2>&1 || failed=1
done
if [[ "${failed}" != 0 ]]; then
  echo "  Failures (blocking):"
  echo "    - tests/unit/test-A.sh"
fi
exit "${failed}"
EOF
  chmod +x "${root}/fake-e2e.sh"
  git -C "${root}" add -A
  git -C "${root}" commit -q -m "fixture: fixed A"

  printf '%s\n' "${a_working}" > "${root}/A.txt"
}

# ── stubs ─────────────────────────────────────────────────────────────────────
TMP="$(lv2_mktemp_dir "e2e-gate-is-advisory-test")"; trap 'rm -rf "$TMP"' EXIT

REDSUITE_E2E="fake-e2e"   # build_fixture writes fake-e2e.sh into each root

STUB_JOURNAL_TAIL_OK=1     # journal stub accepts the arbiter's `tail` probe

mk_journal_stub() { # <name> -> sets ${name}_LOG and ${name}_BIN
  local name="$1"
  eval "${name}_LOG=\"${TMP}/journal-${name}.log\""
  : > "$(eval "printf '%s' \"\${${name}_LOG}\"")"
  local bin="${TMP}/stub-journal-${name}.sh"
  printf '%s\n' '#!/usr/bin/env bash' > "${bin}"
  printf 'printf '"'"'%%s\\n'"'"' "$*" >> %q\n' "$(eval "printf '%s' \"\${${name}_LOG}\"")" >> "${bin}"
  chmod +x "${bin}"
  eval "${name}_BIN=\"${bin}\""
}

STUB_LEDGER_LOG="${TMP}/ledger-calls.log"; : > "${STUB_LEDGER_LOG}"
STUB_LEDGER="${TMP}/stub-ledger.sh"
printf '%s\n' '#!/usr/bin/env bash' > "${STUB_LEDGER}"
printf 'printf '\''%%s\\n'\'' "$*" >> %q\n' "${STUB_LEDGER_LOG}" >> "${STUB_LEDGER}"
printf '%s\n' 'exit 0' >> "${STUB_LEDGER}"
chmod +x "${STUB_LEDGER}"

STUB_DISPATCH="${TMP}/stub-dispatch.sh"
printf '%s\n' '#!/usr/bin/env bash' > "${STUB_DISPATCH}"
printf 'printf '\''%%s\\n'\'' "dispatch $*" >> %q\n' "${STUB_LEDGER_LOG}" >> "${STUB_DISPATCH}"
printf '%s\n' 'exit 0' >> "${STUB_DISPATCH}"
chmod +x "${STUB_DISPATCH}"

# Fail-verdict reviewer: the codex arm launcher is env-overridable, so the stub
# emits the exact contract parse_review_verdict() enforces.
REVIEW_FAIL_BIN="${TMP}/stub-codex-fail.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "REVIEW_VERDICT: FAIL"' \
  'echo "REVIEW_FINDINGS: critical=1 high=0 medium=0 low=0"' \
  'echo "## [Critical] any blocking finding"' \
  'exit 0' > "${REVIEW_FAIL_BIN}"
chmod +x "${REVIEW_FAIL_BIN}"

# Pool resolver stub: reviewer=codex, author will be glm -> no self-review.
RESOLVER_STUB="${TMP}/stub-resolver.py"
printf '%s\n' \
  '#!/usr/bin/env python3' \
  'import sys' \
  'print("reviewer=codex")' \
  'print("pool=codex:ok:")' \
  'print("resolver_rc=0")' > "${RESOLVER_STUB}"

# Keep the route arbiter out of the sandbox decision (the pool stub above is
# the authority here): point both fallback roots at a path that cannot exist.
NO_SUCH_ROOT="${TMP}/definitely-not-a-root"

# ── gate runner ───────────────────────────────────────────────────────────────
run_gate() { # <root> <sig8> <e2e_on> <review_on> <journal_name> [extra env as K=V ...]
  local root="$1" sig8="$2" e2e_on="$3" review_on="$4" jname="$5"; shift 5
  local handoff="${root}/docs/handoff/dispatch-${sig8}"
  rm -rf "${handoff}"
  local jlog jbin
  jlog="${TMP}/journal-${jname}.log"; jbin="${TMP}/stub-journal-${jname}.sh"
  RC=0
  env \
    LEADV2_E2E_CMD="bash ${root}/${REDSUITE_E2E}.sh" \
    LEADV2_E2E_OWNERSHIP=0 \
    LEADV2_DISPATCH_LANE_WRITES="A.txt" \
    LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
    LEADV2_LANE_WORK_ROOT="${root}" \
    LEADV2_DISPATCH_TERMINAL_LEDGER=1 \
    LEADV2_DISPATCH_LEDGER_BIN="${STUB_LEDGER}" \
    LEADV2_JOURNAL_BIN="${jbin}" \
    LEADV2_DISPATCH_BIN="${STUB_DISPATCH}" \
    LEADV2_DISPATCH_CACHE_DIR="${TMP}/cache-${sig8}" \
    LEADV2_GLM_POLICY_RESOLVER="${RESOLVER_STUB}" \
    LEADV2_DISPATCH_CODEX_BIN="${REVIEW_FAIL_BIN}" \
    LEADV2_ROUTE_ARBITER_LIB="${NO_SUCH_ROOT}/route-arbiter.sh" \
    LEADV2_CANONICAL_ROOT="${NO_SUCH_ROOT}" \
    "$@" \
    bash "$PRODUCT_CLOSE_SH" "${root}" "${sig8}" glm "" "${e2e_on}" "${review_on}" "" >/dev/null 2>&1 || RC=$?
  MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
  GATE_LOG="$(cat "${handoff}/e2e-gate.log" 2>/dev/null || true)"
  RGATE_MD="$(cat "${handoff}/review-gate.md" 2>/dev/null || true)"
  JLOG="${TMP}/journal-${jname}.log"
}

# ════════════════════════════════════════════════════════════════════════════
# A1: red e2e, review kill-switch off -> advisory: reported, measured, NOT dead
# ════════════════════════════════════════════════════════════════════════════
A1="${TMP}/a1"; mkdir -p "${A1}"
build_fixture "${A1}" "broken-A"
lv2_assert_scratch_repo "${A1}"
mk_journal_stub "a1"

run_gate "${A1}" "a10sig01" 1 0 "a1"

if [[ "${RC}" -eq 0 ]]; then
  pass "A1: red e2e no longer exits 8 (rc=0 — lane fell through, review off => review_gate_disabled landing)"
else
  fail "A1: expected rc=0 (advisory fall-through), got rc=${RC} md=<${MD}>"
fi

if grep -q 'status: fail' <<<"${MD}" && grep -q 'reason: e2e_regression' <<<"${MD}" \
   && grep -q 'failing_suites: tests/unit/test-A\.sh' <<<"${MD}"; then
  pass "A1: e2e-gate.md still reports status: fail / reason: e2e_regression with the failing suite named"
else
  fail "A1: e2e-gate.md lost the red verdict or the failing-suite name — md=<${MD}>"
fi

if [[ -n "${GATE_LOG}" ]] && grep -q 'e2e-root:' <<<"${GATE_LOG}"; then
  pass "A1: the gate actually RAN — e2e-gate.log is present and non-empty (advisory, not skipped)"
else
  fail "A1: e2e-gate.log missing/empty — an advisory verdict must still be a measured one"
fi

if grep -qE 'decision e2e_gate task=a10sig01 status=ran verdict=fail rc=1' "${JLOG}" \
   && grep -qE 'decision e2e_regression task=a10sig01 status=advisory rc=1 failing_suites=tests/unit/test-A\.sh' "${JLOG}"; then
  pass "A1: journal carries the measured fail verdict AND the advisory decision line"
else
  fail "A1: journal missing verdict=fail or advisory line — $(cat "${JLOG}")"
fi

if grep -qE 'write-terminal a10sig01 .*dead e2e_regression' "${STUB_LEDGER_LOG}"; then
  fail "A1: ledger still recorded dead/e2e_regression — the terminal was not removed"
else
  pass "A1: no dead/e2e_regression terminal in the ledger"
fi

if grep -qE 'write-terminal a10sig01 .*landed review_gate_disabled' "${STUB_LEDGER_LOG}"; then
  pass "A1: fall-through proven — lane terminal is landed/review_gate_disabled (the review-gate region was reached)"
else
  fail "A1: expected landed/review_gate_disabled terminal after fall-through — $(grep 'write-terminal a10sig01' "${STUB_LEDGER_LOG}")"
fi

if [[ -z "${FLAG}" ]]; then
  pass "A1: no e2e-gate-passed.flag — a red verdict is never stamped as a pass"
else
  fail "A1: pass sentinel written for a red e2e — flag=<${FLAG}>"
fi

# Work survival: the lane's uncommitted write is checkpointed (pc_stop_gate_
# autocommit runs before the gate), nothing in the advisory path discards it.
if grep -q 'broken-A' "${A1}/A.txt" 2>/dev/null; then
  pass "A1: lane's own write survives the advisory verdict (checkpoint, not discard)"
else
  fail "A1: A.txt lost its lane content — advisory path must not discard work"
fi

# ════════════════════════════════════════════════════════════════════════════
# A2: review still kills — same red e2e, REVIEW_ON=1, reviewer returns FAIL
# ════════════════════════════════════════════════════════════════════════════
A2="${TMP}/a2"; mkdir -p "${A2}"
build_fixture "${A2}" "broken-A"
lv2_assert_scratch_repo "${A2}"
mk_journal_stub "a2"

run_gate "${A2}" "a20sig01" 1 1 "a2"

if [[ "${RC}" -eq 7 ]]; then
  pass "A2: a failing review still ends the lane non-landed (exit 7)"
else
  fail "A2: expected exit 7 from a FAIL review verdict, got rc=${RC} rgate=<${RGATE_MD}>"
fi

if grep -qE 'write-terminal a20sig01 .*dead review_verdict_fail' "${STUB_LEDGER_LOG}"; then
  pass "A2: ledger terminal is dead/review_verdict_fail — review kept its kill"
else
  fail "A2: no dead/review_verdict_fail terminal — review kill is gone? $(grep 'write-terminal a20sig01' "${STUB_LEDGER_LOG}")"
fi

if grep -q 'status: fail' <<<"${RGATE_MD}"; then
  pass "A2: review-gate.md records the fail verdict"
else
  fail "A2: review-gate.md missing status: fail — rgate=<${RGATE_MD}>"
fi

if [[ -f "${A2}/docs/handoff/dispatch-a20sig01/review-codex.md" ]] \
   && grep -q 'REVIEW_VERDICT: FAIL' "${A2}/docs/handoff/dispatch-a20sig01/review-codex.md"; then
  pass "A2: the reviewer actually ran on the red-e2e lane (fall-through reached the review gate)"
else
  fail "A2: review-codex.md missing/without FAIL marker — review never ran"
fi

if grep -qE 'decision e2e_regression task=a20sig01 status=advisory' "${JLOG}"; then
  pass "A2: the advisory line is present BEFORE the lane's terminal — the red e2e was reported to the reviewer's lane record"
else
  fail "A2: advisory line missing under REVIEW_ON=1 — $(cat "${JLOG}")"
fi

# ════════════════════════════════════════════════════════════════════════════
# A3: kill-switch branch unchanged — E2E_ON=0 is a deliberate disabled state:
# the gate does NOT run, no verdict artifact, no advisory line.
# ════════════════════════════════════════════════════════════════════════════
A3="${TMP}/a3"; mkdir -p "${A3}"
build_fixture "${A3}" "broken-A"
lv2_assert_scratch_repo "${A3}"
mk_journal_stub "a3"

run_gate "${A3}" "a30sig01" 0 0 "a3"

if [[ "${RC}" -eq 0 ]] && grep -qE 'decision e2e_gate task=a30sig01 status=disabled reason=kill_switch' "${JLOG}"; then
  pass "A3: E2E_ON=0 still means kill_switch — gate disabled, lane lands review_gate_disabled"
else
  fail "A3: expected rc=0 + kill_switch journal line, got rc=${RC} — $(cat "${JLOG}")"
fi

if [[ -z "${MD}" ]] && ! grep -q 'decision e2e_regression task=a30sig01' "${JLOG}"; then
  pass "A3: no e2e verdict artifact and no advisory line when the gate is deliberately off"
else
  fail "A3: gate produced a verdict under E2E_ON=0 — md=<${MD}>"
fi

printf -- '\n[TEST] %d passed, %d failed, %d not run\n' "$PASS" "$FAIL" "$NOTRUN"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
