#!/usr/bin/env bash
# E2E-GATE-ARCH-01 — behavioural proof that:
#   (a) the e2e gate runs suites against the LANE WORKTREE (not the main
#       checkout): a lane whose worktree fixes a suite that is RED on main
#       passes the gate, proving lane-tree testing.
#
# Mutation gate (red/green): each case must FAIL when the fix is reverted.
#   (a) revert: force _lv2_e2e_root to ROOT (main checkout) — the red suite
#       on main kills the lane → exit 8.
#
# Run normally for green. To gate against a reverted script:
#   LEADV2_PC_SCRIPT=/path/to/reverted-product-close.sh bash "$0"
#
# Run: bash plugins/leadv2/scripts/tests/test-e2e-gate-arch-01.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

PRODUCT_CLOSE_SH="${LEADV2_PC_SCRIPT:-${SCRIPTS_ROOT}/leadv2-dispatch-product-close.sh}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

# ── fixture: main repo + lane worktree ───────────────────────────────────────
# Suite test-fix-A.sh: passes iff file A.txt contains "fixed".
# On main: A.txt = "broken" (suite RED).
# In worktree: A.txt = "fixed" (suite GREEN).
# If the gate tests main → exit 8 (regression). If it tests worktree → pass.
build_lane_fixture() { # <main_root> <wt_root>
  local main="$1" wt="$2"
  mkdir -p "${main}/plugins/leadv2/scripts/tests" "${main}/tests"
  git -C "${main}" init -q
  git -C "${main}" config user.email test@test.local
  git -C "${main}" config user.name test

  # A.txt is BROKEN on main
  printf 'broken\n' > "${main}/A.txt"

  # Suite that checks A.txt content
  cat > "${main}/plugins/leadv2/scripts/tests/test-fix-A.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
content="$(cat A.txt 2>/dev/null || true)"
if [[ "${content}" == "fixed" ]]; then
  exit 0
else
  echo "FAIL: A.txt is '${content}', expected 'fixed'" >&2
  exit 1
fi
EOF
  chmod +x "${main}/plugins/leadv2/scripts/tests/test-fix-A.sh"

  # run-all.sh entrypoint
  cat > "${main}/tests/run-all.sh" <<'RUNALL'
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
FAIL=0
for suite in "${ROOT}/plugins/leadv2/scripts/tests/"test-*.sh; do
  [[ -f "$suite" ]] || continue
  printf '[RUN] %s\n' "$suite"
  if bash "$suite"; then
    printf '[PASS] %s\n' "$suite"
  else
    FAIL=$((FAIL+1))
    printf '[FAIL] %s\n' "$suite"
  fi
done
if [[ $FAIL -gt 0 ]]; then
  printf '  Failures (blocking):\n'
  for s in "${ROOT}/plugins/leadv2/scripts/tests/"test-*.sh; do
    [[ -f "$s" ]] || continue
    rel="${s#"${ROOT}/"}"
    if ! bash "$s" >/dev/null 2>&1; then
      printf '    - %s\n' "$rel"
    fi
  done
fi
printf 'run-all: %d failed\n' "$FAIL"
(( FAIL == 0 ))
RUNALL
  chmod +x "${main}/tests/run-all.sh"

  git -C "${main}" add -A
  git -C "${main}" commit -q -m "fixture: main with broken A.txt"

  # Create lane worktree with the FIX
  git -C "${main}" worktree add -q "${wt}" HEAD 2>/dev/null
  printf 'fixed\n' > "${wt}/A.txt"
}

# ── gate runner ──────────────────────────────────────────────────────────────
run_gate() { # <root> <worktree> <sig8> <writes_csv> <home_dir> -> RC, MD, FLAG, LOG
  local root="$1" wt="$2" sig8="$3" writes="$4" home_dir="$5"
  local handoff="${root}/docs/handoff/dispatch-${sig8}"
  rm -rf "${handoff}"
  mkdir -p "${home_dir}"
  RC=0
  LEADV2_E2E_CMD="bash ${wt}/tests/run-all.sh" \
  LEADV2_E2E_OWNERSHIP="1" \
  LEADV2_DISPATCH_LANE_WRITES="${writes}" \
  LEADV2_LANE_WORK_ROOT="${wt}" \
  LEADV2_DISPATCH_TERMINAL_LEDGER=0 \
  LEADV2_JOURNAL_BIN=/bin/true \
    env HOME="${home_dir}" \
    bash "$PRODUCT_CLOSE_SH" "${root}" "${sig8}" codex "" 1 0 "" >"${home_dir}/gate.out" 2>&1 || RC=$?
  MD="$(cat "${handoff}/e2e-gate.md" 2>/dev/null || true)"
  FLAG="$(cat "${handoff}/e2e-gate-passed.flag" 2>/dev/null || true)"
  GATE_LOG="$(cat "${handoff}/e2e-gate.log" 2>/dev/null || true)"
}

TMP="$(lv2_mktemp_dir "e2e-gate-arch-01")"; trap 'rm -rf "$TMP"' EXIT
# ════════════════════════════════════════════════════════════════════════════
# Case (a): lane worktree fixes a suite that is RED on main → gate PASSES
# ════════════════════════════════════════════════════════════════════════════
CA="${TMP}/case-a"; CA_WT="${CA}-wt"
mkdir -p "${CA}"
build_lane_fixture "${CA}" "${CA_WT}"
lv2_assert_scratch_repo "${CA}"

run_gate "${CA}" "${CA_WT}" "ea00sig1" "A.txt" "${TMP}/home-a"

if [[ "${RC}" -eq 0 ]] \
  && grep -q "^e2e-root: ${CA_WT}" <<<"${GATE_LOG}" \
  && grep -q 'bypassed: false' <<<"${FLAG}"; then
  pass "(a) lane-tree testing: worktree fix passes gate (rc=0, e2e-root=worktree)"
else
  fail "(a) lane-tree testing: expected rc=0 + e2e-root=${CA_WT} + pass, got rc=${RC} log_first=<$(head -1 <<<"${GATE_LOG}")> flag=<${FLAG}> md=<${MD}>"
fi

# ── summary ─────────────────────────────────────────────────────────────────
printf -- '\n[TEST] %d passed, %d failed\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
