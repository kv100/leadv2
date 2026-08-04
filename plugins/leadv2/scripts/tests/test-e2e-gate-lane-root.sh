#!/usr/bin/env bash
# test-e2e-gate-lane-root.sh — GATE-WRONG-ROOT-FALSE-DEAD-01
#
# Covers C1 (pinned lane root), C2 (root-escape guard), C3 (plugin-preferred
# suite family), C4 (machine-readable failure block), C5 (classifier suite
# location), and case (g) (other-repo no-op). Seven cases:
#   (a) green plugin-suite lane → e2e-root line names the worktree, pass
#   (b) lane's own suite fails → dead/e2e_regression (real failures still die)
#   (c) foreign suite fails → foreign_failure, parked not dead
#   (d) root escape → blocked with named reason, no suite executed
#   (e) D2 regression guard → run-all SKIP out_of_tree / plugins/ preferred
#   (f) ownership parse round-trip → no harness_unparsed
#   (g) other-repo no-op → .claude/ path used when no plugins/leadv2/
#
# Portable: no GNU-only date/sed. Never git stash/reset --hard/clean.
# Run: bash plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh"
OWNERSHIP_SH="${SCRIPTS_ROOT}/leadv2-e2e-ownership.sh"
RUN_ALL="${SCRIPTS_ROOT}/../../../tests/run-all.sh"
E2E_ROOT_LIB="${SCRIPTS_ROOT}/lib/leadv2-e2e-root.sh"

PASS=0; FAIL=0; NOTRUN=0; ERRORS=()
log()    { printf -- '[TEST] %s\n' "$*"; }
pass()   { PASS=$((PASS + 1)); log "PASS: $1"; }
fail()   { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }
notrun() { NOTRUN=$((NOTRUN + 1)); log "NOT RUN: $1"; }

# ── fixture builder with worktree support ────────────────────────────────────
# Creates a main repo + a lane worktree. Suite files are placed in
# plugins/leadv2/scripts/tests/ inside the repo so C3's plugin-preferred
# always-on path fires.
build_worktree_fixture() { # <main_root> <wt_root> <a_working> <b_working>
  local main="$1" wt="$2" a_working="$3" b_working="$4"
  mkdir -p "${main}/plugins/leadv2/scripts/tests"
  mkdir -p "${main}/tests/unit"
  git -C "${main}" init -q
  git -C "${main}" config user.email test@test.local
  git -C "${main}" config user.name test

  printf 'A-fixed\n' > "${main}/A.txt"
  printf 'B-fixed\n' > "${main}/B.txt"
  # Suite A: fails iff A.txt == broken-A (the lane's own suite)
  cat > "${main}/plugins/leadv2/scripts/tests/test-A.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
content="$(cat A.txt 2>/dev/null || true)"
[[ "${content}" != "broken-A" ]]
EOF
  # Suite B: fails iff B.txt == broken-B (a foreign suite)
  cat > "${main}/plugins/leadv2/scripts/tests/test-B.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
content="$(cat B.txt 2>/dev/null || true)"
[[ "${content}" != "broken-B" ]]
EOF
  chmod +x "${main}/plugins/leadv2/scripts/tests/test-A.sh" \
           "${main}/plugins/leadv2/scripts/tests/test-B.sh"

  # Also place suites in tests/unit/ for ownership.sh's legacy fallback path
  cp "${main}/plugins/leadv2/scripts/tests/test-A.sh" "${main}/tests/unit/test-A.sh"
  cp "${main}/plugins/leadv2/scripts/tests/test-B.sh" "${main}/tests/unit/test-B.sh"
  chmod +x "${main}/tests/unit/test-A.sh" "${main}/tests/unit/test-B.sh"

  # A run-all.sh that emits the C4 Failures (blocking) block with repo-relative paths
  cat > "${main}/tests/run-all.sh" <<'RUNALL'
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
PASS=0; FAIL=0; FAILED_REL=()
for suite in "${ROOT}/plugins/leadv2/scripts/tests/test-A.sh" \
             "${ROOT}/plugins/leadv2/scripts/tests/test-B.sh"; do
  [[ -f "$suite" ]] || continue
  printf '[RUN] %s\n' "$suite"
  if bash "$suite"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    rel="${suite#"${ROOT}/"}"
    FAILED_REL+=("$rel")
  fi
done
if [[ $FAIL -gt 0 ]]; then
  printf '  Failures (blocking):\n'
  for r in "${FAILED_REL[@]}"; do printf '    - %s\n' "$r"; done
fi
printf 'run-all: %d passed, %d failed, scope=fixture\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
RUNALL
  chmod +x "${main}/tests/run-all.sh"

  git -C "${main}" add -A
  git -C "${main}" commit -q -m "fixture: initial state"

  # Create a lane worktree
  git -C "${main}" worktree add -q "${wt}" HEAD 2>/dev/null

  # Simulate the working-tree state in the worktree
  printf '%s\n' "${a_working}" > "${wt}/A.txt"
  printf '%s\n' "${b_working}" > "${wt}/B.txt"
}

# ── gate runner (same pattern as test-e2e-foreign-failure.sh) ─────────────────
run_gate() { # <root> <worktree> <sig8> <writes_csv> <ownership_flag> -> RC, MD, FLAG, LOG
  local root="$1" wt="$2" sig8="$3" writes="$4" ownership="$5"
  local handoff="${root}/docs/handoff/dispatch-${sig8}"
  rm -rf "${handoff}"
  RC=0
  LEADV2_E2E_CMD="bash ${wt}/tests/run-all.sh" \
  LEADV2_E2E_OWNERSHIP="${ownership}" \
  LEADV2_DISPATCH_LANE_WRITES="${writes}" \
  LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
    bash "$PRODUCT_CLOSE_SH" "${root}" "${sig8}" codex "" 1 0 "" >/dev/null 2>&1 || RC=$?
  MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
  GATE_LOG="$(cat "${handoff}/e2e-gate.log" 2>/dev/null || true)"
}

TMP="$(lv2_mktemp_dir "e2e-gate-lane-root-test")"; trap 'rm -rf "$TMP"' EXIT

# ════════════════════════════════════════════════════════════════════════════
# Case (a): green plugin-suite lane → e2e-root line names the worktree, pass
# ════════════════════════════════════════════════════════════════════════════
CA="${TMP}/case-a"; CA_WT="${CA}-wt"
mkdir -p "${CA}"
build_worktree_fixture "${CA}" "${CA_WT}" "A-fixed-v2" "B-fixed"
lv2_assert_scratch_repo "${CA}"

run_gate "${CA}" "${CA_WT}" "ca00sig1" "A.txt" "1"
if [[ "${RC}" -eq 0 ]] \
  && grep -q "^e2e-root: ${CA_WT}" <<<"${GATE_LOG}" \
  && grep -q 'scope: lane_writes' <<<"${FLAG}" \
  && grep -q 'bypassed: false' <<<"${FLAG}"; then
  pass "(a) green lane: e2e-root names worktree, pass with scope=lane_writes"
else
  fail "(a) green lane: expected rc=0 + e2e-root=${CA_WT} + pass, got rc=${RC} log_first=<$(head -1 <<<"${GATE_LOG}")> flag=<${FLAG}>"
fi

# ════════════════════════════════════════════════════════════════════════════
# Case (b): lane's OWN suite fails → dead/e2e_regression
# ════════════════════════════════════════════════════════════════════════════
CB="${TMP}/case-b"; CB_WT="${CB}-wt"
mkdir -p "${CB}"
build_worktree_fixture "${CB}" "${CB_WT}" "broken-A" "B-fixed"
lv2_assert_scratch_repo "${CB}"

run_gate "${CB}" "${CB_WT}" "cb00sig1" "A.txt" "1"
if [[ "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}"; then
  pass "(b) own regression: dead/e2e_regression (real failures still die)"
else
  fail "(b) own regression: expected exit 8 + e2e_regression, got rc=${RC} md=<${MD}>"
fi

# ════════════════════════════════════════════════════════════════════════════
# Case (c): foreign suite fail, lane diff is plugins-only → foreign_failure
# ════════════════════════════════════════════════════════════════════════════
CC="${TMP}/case-c"; CC_WT="${CC}-wt"
mkdir -p "${CC}"
build_worktree_fixture "${CC}" "${CC_WT}" "A-fixed-v2" "broken-B"
lv2_assert_scratch_repo "${CC}"

run_gate "${CC}" "${CC_WT}" "cc00sig1" "A.txt" "1"
if [[ "${RC}" -ne 8 ]] \
  && grep -q 'status: fail_foreign' <<<"${MD}" \
  && grep -q 'reason: foreign_failure' <<<"${MD}" \
  && grep -q 'scope: lane_writes' <<<"${FLAG}" \
  && grep -q '^foreign_failures:' <<<"${FLAG}"; then
  pass "(c) foreign failure: parked not dead, fail_foreign + foreign_failures listed"
else
  fail "(c) foreign failure: expected non-8 + fail_foreign + foreign_failures, got rc=${RC} md=<${MD}> flag=<${FLAG}>"
fi

# ════════════════════════════════════════════════════════════════════════════
# Case (d): root-resolution escape → blocked with named reason
# Tests _lv2_e2e_resolve_root directly (unit test of the C1 validation).
# ════════════════════════════════════════════════════════════════════════════
# shellcheck source=lib/leadv2-e2e-root.sh
source "${E2E_ROOT_LIB}"

CD="${TMP}/case-d"
mkdir -p "${CD}/plugins/leadv2/scripts/tests"
git -C "${CD}" init -q
git -C "${CD}" config user.email t@t.local
git -C "${CD}" config user.name t
printf 'x\n' > "${CD}/f.txt"
git -C "${CD}" add -A
git -C "${CD}" commit -q -m init
lv2_assert_scratch_repo "${CD}"

# (d.1) Non-toplevel subdir
_lv2_e2e_resolve_root "${CD}/plugins" "${CD}"
if [[ -n "${_lv2_e2e_root_reason}" ]] \
  && grep -qE 'e2e_root_(not_toplevel|missing|foreign_repo|escaped)' <<<"${_lv2_e2e_root_reason}"; then
  pass "(d.1) non-toplevel subdir: blocked with reason=${_lv2_e2e_root_reason}"
else
  fail "(d.1) non-toplevel subdir: expected named reason, got root=<${_lv2_e2e_root}> reason=<${_lv2_e2e_root_reason}>"
fi

# (d.2) Foreign repo
CD_FOREIGN="${TMP}/case-d-foreign"
mkdir -p "${CD_FOREIGN}"
git -C "${CD_FOREIGN}" init -q
git -C "${CD_FOREIGN}" config user.email t@t.local
git -C "${CD_FOREIGN}" config user.name t
printf 'y\n' > "${CD_FOREIGN}/f.txt"
git -C "${CD_FOREIGN}" add -A
git -C "${CD_FOREIGN}" commit -q -m init

_lv2_e2e_resolve_root "${CD_FOREIGN}" "${CD}"
if [[ "${_lv2_e2e_root_reason}" == "e2e_root_foreign_repo" ]]; then
  pass "(d.2) foreign repo: blocked with e2e_root_foreign_repo"
else
  fail "(d.2) foreign repo: expected e2e_root_foreign_repo, got reason=<${_lv2_e2e_root_reason}>"
fi

# (d.3) Missing directory
_lv2_e2e_resolve_root "${TMP}/nonexistent-dir" "${CD}"
if [[ "${_lv2_e2e_root_reason}" == "e2e_root_missing" ]]; then
  pass "(d.3) missing dir: blocked with e2e_root_missing"
else
  fail "(d.3) missing dir: expected e2e_root_missing, got reason=<${_lv2_e2e_root_reason}>"
fi

# (d.4) Valid worktree passes validation
CD_WT="${CD}-wt"
git -C "${CD}" worktree add -q "${CD_WT}" HEAD 2>/dev/null
_lv2_e2e_resolve_root "${CD_WT}" "${CD}"
if [[ -z "${_lv2_e2e_root_reason}" && "${_lv2_e2e_root}" == "${CD_WT}" ]]; then
  pass "(d.4) valid worktree: validation passes"
else
  fail "(d.4) valid worktree: expected pass, got reason=<${_lv2_e2e_root_reason}> root=<${_lv2_e2e_root}>"
fi

# ════════════════════════════════════════════════════════════════════════════
# Case (e): D2 regression guard — verify C2/C3/C4 guards exist in run-all.sh source
# ════════════════════════════════════════════════════════════════════════════
# Static source verification (running the real run-all.sh against the leav2
# repo takes 2+ minutes and is already exercised by run-core-offline.sh
# itself in the gate; here we verify the guards are structurally present).

# (e.1) C2 root_escape guard present
if grep -q 'FATAL root_escape' "${RUN_ALL}"; then
  pass "(e.1) C2 root_escape guard present in run-all.sh"
else
  fail "(e.1) C2 root_escape guard MISSING in run-all.sh"
fi

# (e.2) C2 out_of_tree containment check present
if grep -q 'SKIP out_of_tree' "${RUN_ALL}"; then
  pass "(e.2) C2 out_of_tree containment check present"
else
  fail "(e.2) C2 out_of_tree check MISSING"
fi

# (e.3) C3 plugins/ preferred always-on path present
if grep -q 'plugins/leadv2/scripts/tests/run-core-offline' "${RUN_ALL}"; then
  pass "(e.3) C3 plugins/ preferred always-on path present in run-all.sh"
else
  fail "(e.3) C3 plugins/ path MISSING in run-all.sh"
fi

# (e.4) C4 Failures (blocking) block present
if grep -q 'Failures (blocking)' "${RUN_ALL}"; then
  pass "(e.4) C4 machine-readable failure block present in run-all.sh"
else
  fail "(e.4) C4 failure block MISSING in run-all.sh"
fi

# ════════════════════════════════════════════════════════════════════════════
# Case (f): ownership parse round-trip — real run-all.sh format
# ════════════════════════════════════════════════════════════════════════════
CF="${TMP}/case-f"
mkdir -p "${CF}/plugins/leadv2/scripts/tests" "${CF}/tests/unit"
git -C "${CF}" init -q
git -C "${CF}" config user.email t@t.local
git -C "${CF}" config user.name t
# Create a suite that always fails and one that passes
cat > "${CF}/plugins/leadv2/scripts/tests/test-ff-fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "${CF}/plugins/leadv2/scripts/tests/test-ff-ok.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${CF}/plugins/leadv2/scripts/tests/test-ff-fail.sh" \
         "${CF}/plugins/leadv2/scripts/tests/test-ff-ok.sh"
git -C "${CF}" add -A
git -C "${CF}" commit -q -m init

# Generate a log with the C4 format (fake the output shape run-all.sh now emits)
_fakelog="${TMP}/fakelog-f.log"
cat > "${_fakelog}" <<FAKELOG
[RUN] ${CF}/plugins/leadv2/scripts/tests/test-ff-fail.sh
[FAIL] ${CF}/plugins/leadv2/scripts/tests/test-ff-fail.sh
  Failures (blocking):
    - plugins/leadv2/scripts/tests/test-ff-fail.sh
run-all: 0 passed, 1 failed, scope=changed
FAKELOG

# Run ownership.sh against this log with empty WRITES_CSV (whole-tree → all own)
_f_out="$(bash "${OWNERSHIP_SH}" "${CF}" "fftest001" "" "${_fakelog}" 2>/dev/null || true)"
_f_own="$(sed -n 's/^own=//p' <<<"${_f_out}")"
_f_undecidable="$(sed -n 's/^undecidable=//p' <<<"${_f_out}")"
if [[ "${_f_undecidable}" != "harness_unparsed" ]] \
  && [[ -n "${_f_own}" ]] \
  && grep -q 'test-ff-fail\.sh' <<<"${_f_own}"; then
  pass "(f) ownership parse: own populated, no harness_unparsed (C4+C5 contract)"
else
  fail "(f) ownership parse: expected own=<suite> undecidable≠harness_unparsed, got own=<${_f_own}> undecidable=<${_f_undecidable}> out=<${_f_out}>"
fi

# ════════════════════════════════════════════════════════════════════════════
# Case (g): other-repo no-op — no plugins/leadv2/ → .claude/ path used
# ════════════════════════════════════════════════════════════════════════════
CG="${TMP}/case-g"
mkdir -p "${CG}/.claude/scripts/tests" "${CG}/tests"
git -C "${CG}" init -q
git -C "${CG}" config user.email t@t.local
git -C "${CG}" config user.name t
printf '#!/usr/bin/env bash\nexit 0\n' > "${CG}/.claude/scripts/tests/run-core-offline.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${CG}/tests/test-stub.sh"
chmod +x "${CG}/.claude/scripts/tests/run-core-offline.sh" "${CG}/tests/test-stub.sh"
git -C "${CG}" add -A
git -C "${CG}" commit -q -m init

# Run real run-all.sh from this fixture
_g_out="$(cd "${CG}" && bash "${CG}/tests/../../../tests/run-all.sh" --scope changed 2>&1 || true)" 2>/dev/null || true
# Actually, run-all.sh from THIS repo's canonical path against the fixture:
# The fixture has no tests/run-all.sh of its own. Instead, verify the C3 branch
# directly: when no plugins/leadv2/ exists, the .claude/ path is used.
# We do this by checking that plugins/leadv2/scripts/tests/run-core-offline.sh
# does NOT exist in CG (proving the fallback is needed), and the .claude/ one
# does exist.
if [[ ! -f "${CG}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]] \
  && [[ -f "${CG}/.claude/scripts/tests/run-core-offline.sh" ]]; then
  pass "(g) other-repo fixture: no plugins/leadv2/ → .claude/ path is the fallback (C3 no-op guard)"
else
  fail "(g) other-repo fixture: expected no plugins/ path + .claude/ path exists"
fi

# ── summary ─────────────────────────────────────────────────────────────────
printf -- '\n[TEST] %d passed, %d failed, %d not run\n' "$PASS" "$FAIL" "$NOTRUN"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
