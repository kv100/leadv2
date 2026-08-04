#!/usr/bin/env bash
# tests/test-e2e-foreign-failure.sh — GATE-FOREIGN-FAILURE-01 red-first coverage.
#
# Reconstructs the 2026-07-31 05:06-05:19Z shape: a lane's blocking e2e suite
# fails only because ANOTHER lane's file, mid-edit in the same shared working
# tree, is broken -- not because of anything the lane itself wrote. Drives the
# REAL leadv2-dispatch-product-close.sh (never a reimplementation of its gate
# logic).
#
# "Pre-fix" comparison uses LEADV2_E2E_OWNERSHIP=0, not a checked-out prior
# commit: the design's own kill-switch contract (leadv2-dispatch-product-
# close.sh, leadv2-phase8-e2e-gate.sh) states it "restores today's whole-tree
# kill exactly", so it is a byte-identical, git-history-independent stand-in
# for pre-fix behaviour that stays valid for as long as this test exists (a
# `git archive HEAD` snapshot would stop proving anything the moment this
# fix's own commit lands). The literal historical reproduction against the
# actual pre-commit script -- required once by this task's red-first mandate
# -- is captured separately in the task deliverable, not in this permanent
# test.
#
# R1/R4 fixtures assert BOTH sides of that switch: OWNERSHIP=0 must still
# reproduce today's kill (dead/e2e_regression) -- proving the switch is a
# faithful revert -- and OWNERSHIP=1 (default) must NOT kill a pure foreign
# failure. R2/R3/R5 are regression guards: they must NOT change shape between
# the two settings ("did not become permissive").
#
# Portable: no GNU-only date/sed/timeout. Never git stash/reset --hard/clean.
# Run: bash scripts/tests/test-e2e-foreign-failure.sh
# Exit 0 = all pass; non-zero = failures found.
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

# ── fixture builder ──────────────────────────────────────────────────────────
# a_content/b_content: committed ("fixed") vs current working-tree content for
# the two files a fake suite pair depends on. tests/unit/test-A.sh fails iff
# A.txt == "broken-A"; tests/unit/test-B.sh fails iff B.txt == "broken-B".
build_fixture() { # <root> <a_working> <b_working>
  local root="$1" a_working="$2" b_working="$3"
  mkdir -p "${root}/tests/unit"
  git -C "${root}" init -q
  git -C "${root}" config user.email test@test.local
  git -C "${root}" config user.name test

  printf 'A-fixed\n' > "${root}/A.txt"
  printf 'B-fixed\n' > "${root}/B.txt"
  cat > "${root}/tests/unit/test-A.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
content="$(cat A.txt 2>/dev/null || true)"
[[ "${content}" != "broken-A" ]]
EOF
  cat > "${root}/tests/unit/test-B.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
content="$(cat B.txt 2>/dev/null || true)"
[[ "${content}" != "broken-B" ]]
EOF
  chmod +x "${root}/tests/unit/test-A.sh" "${root}/tests/unit/test-B.sh"
  cat > "${root}/fake-e2e.sh" <<'EOF'
#!/usr/bin/env bash
# fixture-only fake e2e entrypoint. Mirrors tests/run-all.sh's exact
# "Failures (blocking):" summary block (C4, GATE-WRONG-ROOT-FALSE-DEAD-01)
# with repo-relative suite names — the real format ownership.sh parses.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"
failed=()
for f in tests/unit/*.sh; do
  [[ -f "${f}" ]] || continue
  if ! ( env RUN_MODE=dry_run bash "${f}" ) >/dev/null 2>&1; then
    failed+=("${f}")
  fi
done
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "  Failures (blocking):"
  for n in "${failed[@]}"; do echo "    - ${n}"; done
fi
[[ ${#failed[@]} -eq 0 ]]
EOF
  chmod +x "${root}/fake-e2e.sh"
  git -C "${root}" add -A
  git -C "${root}" commit -q -m "fixture: fixed A + B"

  # Simulate the working-tree state under test (uncommitted, exactly like a
  # live shared-tree lane mid-edit).
  printf '%s\n' "${a_working}" > "${root}/A.txt"
  printf '%s\n' "${b_working}" > "${root}/B.txt"
}

# ── gate runner ───────────────────────────────────────────────────────────────
run_gate() { # <root> <sig8> <writes_csv> <ownership_flag> -> sets RC, MD, FLAG
  local root="$1" sig8="$2" writes="$3" ownership="$4"
  local handoff="${root}/docs/handoff/dispatch-${sig8}"
  rm -rf "${handoff}"
  RC=0
  # C1 (GATE-WRONG-ROOT-FALSE-DEAD-01): CROSS_REPO_DIFF=0 so diff_root stays
  # ROOT (no worktree lookup that would resolve into the real leadv2 repo).
  LEADV2_E2E_CMD="bash ${root}/fake-e2e.sh" \
  LEADV2_E2E_OWNERSHIP="${ownership}" \
  LEADV2_DISPATCH_LANE_WRITES="${writes}" \
  LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
    bash "$PRODUCT_CLOSE_SH" "${root}" "${sig8}" codex "" 1 0 "" >/dev/null 2>&1 || RC=$?
  MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
}

TMP="$(lv2_mktemp_dir "e2e-foreign-failure-test")"; trap 'rm -rf "$TMP"' EXIT

# ── R1: lane writes A only; B broken (this morning's exact shape) ───────────
# a_working differs from committed A-fixed (creates a diff for the gate);
# test-A.sh still passes since A-fixed-v2 != broken-A.
R1="${TMP}/r1"; mkdir -p "${R1}"
build_fixture "${R1}" "A-fixed-v2" "broken-B"
lv2_assert_scratch_repo "${R1}"

run_gate "${R1}" "r1sig001" "A.txt" "0"
if [[ "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}"; then
  pass "R1 pre-fix-equivalent (OWNERSHIP=0): reproduces the kill (dead/e2e_regression)"
else
  fail "R1 pre-fix-equivalent: expected exit 8 + e2e_regression, got rc=${RC} md=<${MD}>"
fi

run_gate "${R1}" "r1sig002" "A.txt" "1"
if [[ "${RC}" -ne 8 ]] \
  && grep -q 'status: fail_foreign' <<<"${MD}" \
  && grep -q 'reason: foreign_failure' <<<"${MD}" \
  && grep -q 'foreign_files:.*B\.txt' <<<"${MD}" \
  && grep -q 'scope: lane_writes' <<<"${FLAG}" \
  && grep -q '^foreign_failures: tests/unit/test-B\.sh$' <<<"${FLAG}"; then
  pass "R1 post-fix (OWNERSHIP=1): foreign_failure, lane NOT killed, B.txt named"
else
  fail "R1 post-fix: expected non-8 rc + fail_foreign + foreign_files naming B.txt, got rc=${RC} md=<${MD}> flag=<${FLAG}>"
fi

# ── R2: lane writes B (its own regression) ──────────────────────────────────
R2="${TMP}/r2"; mkdir -p "${R2}"
build_fixture "${R2}" "A-fixed" "broken-B"
lv2_assert_scratch_repo "${R2}"

run_gate "${R2}" "r2sig001" "B.txt" "0"
prefix_r2_dead=0
[[ "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}" && prefix_r2_dead=1

run_gate "${R2}" "r2sig002" "B.txt" "1"
if [[ "${prefix_r2_dead}" -eq 1 && "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}"; then
  pass "R2 (own regression, green pre-fix by design -- both settings still kill it): unchanged"
else
  fail "R2: own regression must kill under BOTH settings (this is a permissiveness guard, not new-red evidence) -- pre-fix-dead=${prefix_r2_dead} post-fix rc=${RC} md=<${MD}>"
fi

# ── R3: lane writes A and B; both suites red (mixed -- own must win) ────────
R3="${TMP}/r3"; mkdir -p "${R3}"
build_fixture "${R3}" "broken-A" "broken-B"
lv2_assert_scratch_repo "${R3}"

run_gate "${R3}" "r3sig001" "A.txt,B.txt" "0"
prefix_r3_dead=0
[[ "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}" && prefix_r3_dead=1

run_gate "${R3}" "r3sig002" "A.txt,B.txt" "1"
if [[ "${prefix_r3_dead}" -eq 1 && "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}"; then
  pass "R3 (mixed, green pre-fix by design -- own-wins guard): unchanged, still killed"
else
  fail "R3: mixed own+foreign must still kill (own wins, no laundering) -- pre-fix-dead=${prefix_r3_dead} post-fix rc=${RC} md=<${MD}>"
fi

# ── R4: WRITES_CSV empty; B broken -> whole-tree fallback, loudly marked ────
R4="${TMP}/r4"; mkdir -p "${R4}"
build_fixture "${R4}" "A-fixed" "broken-B"
lv2_assert_scratch_repo "${R4}"

run_gate "${R4}" "r4sig001" "" "0"
prefix_r4_dead=0
[[ "${RC}" -eq 8 ]] && grep -q 'reason: e2e_regression' <<<"${MD}" && prefix_r4_dead=1

run_gate "${R4}" "r4sig002" "" "1"
if [[ "${prefix_r4_dead}" -eq 1 && "${RC}" -eq 8 ]] \
  && grep -q 'reason: e2e_regression' <<<"${MD}" \
  && grep -q 'scope: whole_tree_fallback' <<<"${MD}"; then
  pass "R4 (empty WRITES_CSV): still kills, now WITH scope: whole_tree_fallback recorded (new-red)"
else
  fail "R4: expected dead+e2e_regression+whole_tree_fallback marker, pre-fix-dead=${prefix_r4_dead} post-fix rc=${RC} md=<${MD}>"
fi

# ── R5: all suites green ─────────────────────────────────────────────────────
R5="${TMP}/r5"; mkdir -p "${R5}"
build_fixture "${R5}" "A-fixed-v2" "B-fixed"
lv2_assert_scratch_repo "${R5}"

run_gate "${R5}" "r5sig001" "A.txt" "1"
if [[ "${RC}" -eq 0 ]] && grep -q 'scope: lane_writes' <<<"${FLAG}" && grep -q 'bypassed: false' <<<"${FLAG}"; then
  pass "R5 (all green, post-fix): pass, flag stamped scope: lane_writes"
else
  fail "R5: expected pass with scope: lane_writes, got rc=${RC} flag=<${FLAG}>"
fi

# ── journal-line loudness contract (mission's real trap: silent tolerance) ──
JOURNAL_LOG="${TMP}/journal.log"
: > "${JOURNAL_LOG}"
STUB_JOURNAL="${TMP}/stub-journal.sh"
cat > "${STUB_JOURNAL}" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${JOURNAL_LOG}"
STUB
chmod +x "${STUB_JOURNAL}"

R6="${TMP}/r6"; mkdir -p "${R6}"
build_fixture "${R6}" "A-fixed-v2" "broken-B"
lv2_assert_scratch_repo "${R6}"
handoff6="${R6}/docs/handoff/dispatch-r6sig001"
rm -rf "${handoff6}"
LEADV2_E2E_CMD="bash ${R6}/fake-e2e.sh" \
LEADV2_E2E_OWNERSHIP=1 \
LEADV2_DISPATCH_LANE_WRITES="A.txt" \
LEADV2_REVIEW_DIFF_CROSS_REPO=0 \
LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
LEADV2_JOURNAL_BIN="${STUB_JOURNAL}" \
  bash "$PRODUCT_CLOSE_SH" "${R6}" "r6sig001" codex "" 1 0 "" >/dev/null 2>&1 || true

if grep -qE '^append dispatch-r6sig001 decision e2e_gate task=r6sig001 status=ran verdict=foreign_failure scope=lane_writes foreign_suites=tests/unit/test-B\.sh foreign_files=B\.txt owner_lane=unknown own_failures=0$' "${JOURNAL_LOG}"; then
  pass "loudness (1/4): exact journal decision line present"
else
  fail "loudness (1/4): missing/mismatched e2e_gate decision line -- $(cat "${JOURNAL_LOG}")"
fi
if grep -qE '^append dispatch-r6sig001 decision foreign_failure task=r6sig001 suite=tests/unit/test-B\.sh file=B\.txt owner_lane=unknown$' "${JOURNAL_LOG}"; then
  pass "loudness (2/4): separate per-suite foreign_failure line present"
else
  fail "loudness (2/4): missing per-suite foreign_failure line -- $(cat "${JOURNAL_LOG}")"
fi
md6="$(cat "${handoff6}/e2e-gate.md" 2>/dev/null || true)"
if grep -q 'status: fail_foreign' <<<"${md6}"; then
  pass "loudness (3/4): e2e-gate.md carries status: fail_foreign"
else
  fail "loudness (3/4): e2e-gate.md missing status: fail_foreign -- ${md6}"
fi
flag6="$(cat "${handoff6}/e2e-gate-passed.flag" 2>/dev/null || true)"
if [[ -n "${flag6}" ]]; then
  pass "loudness (4/4): annotated sentinel written for a foreign_failure"
else
  fail "loudness (4/4): sentinel missing for a foreign_failure"
fi

printf -- '\n[TEST] %d passed, %d failed, %d not run\n' "$PASS" "$FAIL" "$NOTRUN"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
