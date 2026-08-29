#!/usr/bin/env bash
# tests/test-e2e-gate-bypass-hardening.sh — CLOSE-GATE-BYPASSABLE-BY-ENV-01
# regression coverage for the 08-17 hardening merged UP into canonical
# (MERGE-UP-PHASE8-GATES-01).
#
# Proves, against the SHIPPED scripts (real subprocesses, real exit codes):
#   L1  PE_SKIP_TESTS=1 is IGNORED by the close gate (push-gate variable): a
#       green suite still runs and the sentinel is stamped bypassed: false.
#   L1b The gate's own bypass LEADV2_E2E_GATE_BYPASS=1 works ONLY with a
#       non-empty LEADV2_E2E_GATE_BYPASS_REASON (fail-closed on empty, no
#       sentinel written) and stamps bypassed: true + bypass_reason:.
#   L2  leadv2-phase8-assert.sh A7 fails closed on a bypassed sentinel with
#       NO bypass_reason (incl. the old PE_SKIP_TESTS sentinel shape), and
#       still passes one bypassed WITH a reason.
#   DRIFT guard: both shipped files still carry the CLOSE-GATE-BYPASSABLE-
#       BY-ENV-01 markers.
#
# Mutation gate (red/green): run with
#   LEADV2_E2E_GATE_SH=/path/to/reverted-gate.sh bash "$0"
# — reverting the L1 hunk (honouring PE_SKIP_TESTS again) flips Test 1 to fail.
#
# Portable: no GNU-only date/sed. Never git stash/reset --hard/clean.
# Run: bash plugins/leadv2/scripts/tests/test-e2e-gate-bypass-hardening.sh
# Exit 0 = all pass; non-zero = failures found.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPTS_ROOT}/leadv2-temp.sh"

GATE_SH="${LEADV2_E2E_GATE_SH:-${SCRIPTS_ROOT}/leadv2-phase8-e2e-gate.sh}"
ASSERT_SH="${LEADV2_PHASE8_ASSERT_SH:-${SCRIPTS_ROOT}/leadv2-phase8-assert.sh}"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

TMP="$(lv2_mktemp_dir "e2e-bypass-hardening-test")"
trap 'rm -rf "$TMP"' EXIT

# ── e2e-gate fixture: green suite, non-empty lane diff ──────────────────────
# args: task_id -> prints the fixture root; sets GATE_RC / GATE_FLAG / GATE_ERR
new_gate_fixture() { # <task_id>
  local task_id="$1"
  local root="${TMP}/gate-${task_id}.$$.${RANDOM}"
  mkdir -p "${root}/tests" "${root}/docs/handoff"
  git -C "${root}" init -q
  git -C "${root}" config user.email test@test.local
  git -C "${root}" config user.name test
  cat > "${root}/tests/run-all.sh" <<'EOF'
#!/usr/bin/env bash
# fixture suite: green, accepts --scope per the entrypoint contract
exit 0
EOF
  chmod +x "${root}/tests/run-all.sh"
  git -C "${root}" add -A
  git -C "${root}" commit -q -m "fixture: green suite"
  printf 'lane work\n' > "${root}/lane-work.txt"   # untracked -> lane not "empty"
  printf '%s' "$root"
}

run_gate() { # <root> <task_id> [extra env as VAR=VAL ...]
  local root="$1" task_id="$2"; shift 2
  rm -f "${root}/docs/handoff/${task_id}/e2e-gate-passed.flag"
  set +e
  GATE_ERR="$(env CLAUDE_PROJECT_ROOT="$root" LEADV2_PROJECT_ROOT="$root" \
    LEADV2_HANDOFF_DIR="${root}/docs/handoff" \
    LEADV2_LANE_WORK_ROOT="$root" \
    LEADV2_JOURNAL_BIN=/bin/true \
    "$@" bash "$GATE_SH" "$task_id" 2>&1 >/dev/null)"
  GATE_RC=$?
  set -e
  GATE_FLAG="$(cat "${root}/docs/handoff/${task_id}/e2e-gate-passed.flag" 2>/dev/null || true)"
}

# ── phase8-assert fixture: every hard assertion except A7 satisfied ─────────
# args: task_id sentinel_body -> prints the fixture root; sets A_RC / A_ERR
new_assert_fixture() { # <task_id> <sentinel_body>
  local task_id="$1" body="$2"
  local root="${TMP}/assert-${task_id}.$$.${RANDOM}"
  mkdir -p "${root}/docs/leadv2/closed" "${root}/docs/handoff/${task_id}"
  printf -- 'task_id: %s\nclosed_at: 2026-01-01T00:00:00Z\n' "$task_id" \
    > "${root}/docs/leadv2/closed/${task_id}.yaml"                        # A1
  printf -- 'entries:\n  - task: %s\n' "$task_id" \
    > "${root}/docs/leadv2/reflect-history.yaml"                          # A4
  printf -- 'total_open: 1\ntasks:\n  - id: %s\n    status: done\n' "$task_id" \
    > "${root}/docs/tasks.yaml"                                           # A2
  printf -- '%s\n' "$body" \
    > "${root}/docs/handoff/${task_id}/e2e-gate-passed.flag"              # A7 (under test)
  printf -- '%s' "$root"
}

run_assert() { # <root> <task_id>
  local root="$1" task_id="$2"
  set +e
  A_ERR="$(CLAUDE_PROJECT_ROOT="$root" LEADV2_PROJECT_ROOT="$root" \
    LEADV2_STATE_ROOT="${root}/.state" \
    bash "$ASSERT_SH" "$task_id" 2>&1 >/dev/null)"
  A_RC=$?
  set -e
}

# ── Test 1 (L1): PE_SKIP_TESTS=1 must NOT bypass the close gate ──────────────
root="$(new_gate_fixture bh-t1)"
run_gate "$root" bh-t1 PE_SKIP_TESTS=1
if [[ "${GATE_RC}" -eq 0 ]] && grep -q '^bypassed: false$' <<<"${GATE_FLAG}"; then
  pass "Test 1 (L1): PE_SKIP_TESTS=1 ignored — tests ran, sentinel stamped bypassed: false"
else
  fail "Test 1 (L1): expected rc=0 + bypassed: false, got rc=${GATE_RC} flag=<${GATE_FLAG}> err=${GATE_ERR}"
fi

# ── Test 2 (L1b): own bypass WITH reason -> visible bypassed sentinel ───────
root="$(new_gate_fixture bh-t2)"
run_gate "$root" bh-t2 LEADV2_E2E_GATE_BYPASS=1 LEADV2_E2E_GATE_BYPASS_REASON="emergency hotfix window"
if [[ "${GATE_RC}" -eq 0 ]] \
  && grep -q '^bypassed: true$' <<<"${GATE_FLAG}" \
  && grep -q '^bypass_reason: emergency hotfix window$' <<<"${GATE_FLAG}"; then
  pass "Test 2 (L1b): LEADV2_E2E_GATE_BYPASS with reason -> bypassed: true + bypass_reason stamped"
else
  fail "Test 2 (L1b): expected rc=0 + bypassed:true + reason, got rc=${GATE_RC} flag=<${GATE_FLAG}> err=${GATE_ERR}"
fi

# ── Test 3 (L1b): own bypass WITHOUT reason -> fail-closed, no sentinel ─────
root="$(new_gate_fixture bh-t3)"
run_gate "$root" bh-t3 LEADV2_E2E_GATE_BYPASS=1
if [[ "${GATE_RC}" -ne 0 && -z "${GATE_FLAG}" ]] \
  && grep -q 'requires a non-empty LEADV2_E2E_GATE_BYPASS_REASON' <<<"${GATE_ERR}"; then
  pass "Test 3 (L1b): reasonless bypass fails closed (rc!=0, no sentinel)"
else
  fail "Test 3 (L1b): expected rc!=0 + no sentinel, got rc=${GATE_RC} flag=<${GATE_FLAG}> err=${GATE_ERR}"
fi

# ── Test 4 (L2): A7 fails closed on a bypassed sentinel with no reason ──────
root="$(new_assert_fixture bh-t4 'e2e-gate-passed: bh-t4
asserted_at: 2026-01-01T00:00:00Z
scope: changed
bypassed: true
deploy_verified: false
deploy_verify_bypassed: false
deploy_verify_bypass_reason: ')"
run_assert "$root" bh-t4
if [[ "${A_RC}" -ne 0 ]] && grep -q 'bypass with no reason' <<<"${A_ERR}"; then
  pass "Test 4 (L2): bypassed sentinel with NO reason -> A7 hard failure"
else
  fail "Test 4 (L2): expected A7 failure, got rc=${A_RC} err=${A_ERR}"
fi

# ── Test 5 (L2): A7 still passes a bypassed sentinel WITH a reason ──────────
root="$(new_assert_fixture bh-t5 'e2e-gate-passed: bh-t5
asserted_at: 2026-01-01T00:00:00Z
scope: changed
bypassed: true
bypass_reason: emergency hotfix window
deploy_verified: false
deploy_verify_bypassed: false
deploy_verify_bypass_reason: ')"
run_assert "$root" bh-t5
if [[ "${A_RC}" -eq 0 ]] && grep -q 'bypassed with reason' <<<"${A_ERR}"; then
  pass "Test 5 (L2): bypassed sentinel WITH reason -> A7 pass (warning logged)"
else
  fail "Test 5 (L2): expected A7 pass with warning, got rc=${A_RC} err=${A_ERR}"
fi

# ── Test 6: drift guard — markers still present in both shipped files ───────
if grep -q 'CLOSE-GATE-BYPASSABLE-BY-ENV-01' "$GATE_SH" && grep -q 'CLOSE-GATE-BYPASSABLE-BY-ENV-01' "$ASSERT_SH" \
  && grep -q 'LEADV2_E2E_GATE_BYPASS_REASON' "$GATE_SH"; then
  pass "Test 6: CLOSE-GATE-BYPASSABLE-BY-ENV-01 markers present in shipped gate + assert"
else
  fail "Test 6: hardening markers missing from $GATE_SH / $ASSERT_SH — drift or bad override path"
fi

log "=== Results: PASS=${PASS} FAIL=${FAIL} ==="
if [[ ${FAIL} -eq 0 ]]; then
  log "All tests passed."
  exit 0
fi
for e in "${ERRORS[@]}"; do log "$e"; done
exit 1
