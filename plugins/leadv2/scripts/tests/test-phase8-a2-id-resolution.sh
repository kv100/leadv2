#!/usr/bin/env bash
# tests/test-phase8-a2-id-resolution.sh — GATE-A2-ID-SCHEME-MISMATCH-01 regression test.
#
# The defect: docs/tasks.yaml can be fingerprint-keyed (persona-engine: each
# row's `id` is an opaque hash, e.g. "ca2177b9451b") while the human
# milestone name a caller has (e.g. "V5-M0-SKELETON-01") only ever appears
# inside `intent`, as the segment before the first ':'. A2's lookup used to
# compare task_id against `id` ONLY, so it could never match a
# fingerprint-keyed row -- the close gate blocked forever, and the failure
# message's own printed remedy (leadv2_tasks_release) hit the identical
# id-only comparison one layer down in leadv2-tasks-lib.sh's "release" op.
#
# Fix: leadv2_tasks_yaml_common.resolve_task() (shared by A2's python block
# and leadv2-tasks-lib.sh's resolve_iid()) matches a row by id OR by
# intent's colon-anchored prefix -- never a substring/startswith, so
# "V5-M1" cannot false-match a row whose intent begins "V5-M10:".
#
# Every fixture below keys rows by an opaque fingerprint id (never
# id==human-name) -- a negative control built only from an id-equals-name
# fixture would not exercise the real defect at all (see Test 2 for the
# separate id-equals-name regression guard).
#
# Run: bash plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh
# Exit 0 = all pass; non-zero = failures found.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-temp.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSERT_SH="${SCRIPTS_DIR}/leadv2-phase8-assert.sh"
TASKS_LIB="${SCRIPTS_DIR}/leadv2-tasks-lib.sh"
COMMON_PY="${SCRIPTS_DIR}/leadv2_tasks_yaml_common.py"

PASS=0; FAIL=0; ERRORS=()
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); log "FAIL: $1"; }

RUN_ID="a2idres-$$-$(date +%s)"
TMPDIR_ROOT="$(lv2_mktemp_dir "${RUN_ID}")"

# The mutation-kill test (below) edits ASSERT_SH in place on the real call
# path -- back it up once here and restore it unconditionally on exit, so a
# failure mid-mutation never leaves the production script poisoned for any
# later suite in the same run-all invocation.
ASSERT_ORIG_BACKUP="${TMPDIR_ROOT}/leadv2-phase8-assert.sh.orig"
cp "$ASSERT_SH" "$ASSERT_ORIG_BACKUP"
_cleanup() {
  cp "$ASSERT_ORIG_BACKUP" "$ASSERT_SH"
  rm -rf "$TMPDIR_ROOT"
}
trap _cleanup EXIT

# ── Extract the A2 python block verbatim from the live script (same pattern
# as test-leadv2-phase8-assert-a2-schema.sh) ────────────────────────────────
_extract_a2_python() {
  awk '/^import sys$/{found=1} found{print} /^PYEOF$/{if(found)exit}' "$ASSERT_SH" | sed '$d'
}

_run_a2() {
  local task_id="$1" tasks_yaml="$2"
  local snippet
  snippet="$(_extract_a2_python)"
  if [[ -z "$snippet" ]]; then
    echo "EXTRACT_FAILED" >&2
    return 99
  fi
  python3 - "$task_id" "$tasks_yaml" \
    "done|poisoned|rejected|failed|archived|closed|completed|admin-closed|verified_closed" \
    "claimed_done|needs_evidence" "$SCRIPTS_DIR" <<PYEOF
$snippet
PYEOF
}

# ── E2E harness (matches test-leadv2-phase8-assert-a2-schema.sh) ────────────
E2E_ROOT="${TMPDIR_ROOT}/e2e"
mkdir -p "$E2E_ROOT"

_e2e_new_project() {
  local task_id="$1"
  local root="${E2E_ROOT}/${task_id}.$$.${RANDOM}"
  mkdir -p "${root}/docs/leadv2/closed" "${root}/docs/handoff/${task_id}"
  printf -- 'task_id: %s\nclosed_at: 2026-01-01T00:00:00Z\n' "$task_id" \
    > "${root}/docs/leadv2/closed/${task_id}.yaml"                                  # A1
  printf -- 'entries:\n  - task: %s\n' "$task_id" \
    > "${root}/docs/leadv2/reflect-history.yaml"                                    # A4
  touch "${root}/docs/handoff/${task_id}/e2e-gate-passed.flag"                      # A7 (fresh)
  printf -- '%s\n' "$root"
}

_e2e_run() {
  local root="$1" task_id="$2"
  set +e
  E2E_ERR="$(CLAUDE_PROJECT_ROOT="$root" LEADV2_PROJECT_ROOT="$root" \
    LEADV2_STATE_ROOT="${root}/.state" \
    bash "$ASSERT_SH" "$task_id" 2>&1 >/dev/null)"
  E2E_RC=$?
  set -e
}

# ── Fixtures — every row keyed by an opaque fingerprint id ─────────────────
FP_YAML="${TMPDIR_ROOT}/fp-tasks.yaml"
cat > "$FP_YAML" <<'EOF'
total_open: 3
tasks:
  - id: ca2177b9451b
    status: done
    intent: 'V5-M0-SKELETON-01: veha M0 plana v5'
  - id: 7ade3187fa02
    status: done
    intent: 'V5-M1: veha M1 plana v5'
  - id: 9c10aa10bb10
    status: in_progress
    intent: 'V5-M10: veha M10 plana v5'
EOF

ID_EQ_YAML="${TMPDIR_ROOT}/id-eq-tasks.yaml"
cat > "$ID_EQ_YAML" <<'EOF'
total_open: 1
tasks:
  - id: V5-M0-SKELETON-01
    status: done
    intent: 'unrelated intent text -- id already equals the task id'
EOF

# ── Test 1: fingerprint-keyed row, intent starts with milestone name -> PASS ──
# This is the real-repo case (V5-M0-SKELETON-01 / ca2177b9451b) the defect
# was reported against; it must be exercised on THIS fixture, not only on a
# row whose id already equals the name.
test_1_fingerprint_intent_prefix_pass() {
  log "Test 1: fingerprint-keyed row, intent starts with milestone name -> A2 PASS"
  local rc=0
  _run_a2 "V5-M0-SKELETON-01" "$FP_YAML" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "Test 1: fingerprint id + intent-prefix match -> exit 0 (PASS)"
  else
    fail "Test 1: expected exit 0, got exit ${rc}"
  fi
}

# ── Test 2: row whose id already equals the task id -> still PASS (regression guard) ──
test_2_id_equals_still_passes() {
  log "Test 2: row whose id equals the task id -> still A2 PASS (regression guard)"
  local rc=0
  _run_a2 "V5-M0-SKELETON-01" "$ID_EQ_YAML" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "Test 2: id==task_id -> exit 0 (PASS, unchanged)"
  else
    fail "Test 2: expected exit 0, got exit ${rc}"
  fi
}

# ── Test 3: anchored match, both directions — no prefix bleed ──────────────
# V5-M1 resolves to its own row (7ade3187fa02, status: done -> PASS, exit 0).
# V5-M10 resolves to ITS OWN row (9c10aa10bb10, status: in_progress -> FAIL
# non-terminal, exit 1) -- NOT "not found" (exit 2), proving V5-M10 is not
# swallowed by V5-M1's row either. A naive startswith() would either
# false-match "V5-M1" onto the "V5-M10:" row, or vice versa; the
# colon-anchor rules both out.
test_3_no_prefix_bleed_both_directions() {
  log "Test 3: V5-M1 must not match V5-M10's row, and vice versa"
  local rc_m1=0 rc_m10=0
  _run_a2 "V5-M1" "$FP_YAML" >/dev/null 2>&1 || rc_m1=$?
  _run_a2 "V5-M10" "$FP_YAML" >/dev/null 2>&1 || rc_m10=$?
  if [[ "$rc_m1" -eq 0 && "$rc_m10" -eq 1 ]]; then
    pass "Test 3: V5-M1 -> its own row (exit 0); V5-M10 -> its own row, non-terminal (exit 1) -- no cross-match either direction"
  else
    fail "Test 3: expected rc_m1=0 rc_m10=1 (each resolves its own row), got rc_m1=${rc_m1} rc_m10=${rc_m10}"
  fi
}

# ── Test 4: genuinely absent task -> FAIL (exit 2), naming what was searched ──
test_4_absent_task_fails() {
  log "Test 4: genuinely absent task -> A2 FAILS (exit 2, not-found, distinct code)"
  local rc=0
  _run_a2 "V5-M99-NOPE" "$FP_YAML" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    pass "Test 4: absent task -> exit 2"
  else
    fail "Test 4: expected exit 2, got exit ${rc}"
  fi
}

# ── Test 4b (E2E): the rc==2 wrapper message names what was actually searched ──
test_4b_e2e_absent_message_names_search() {
  log "Test 4b (E2E): shipped script's rc==2 message names id-or-intent-prefix search, and that only tasks.yaml was consulted"
  local task_id="E2E-ABSENT-$$" root
  root="$(_e2e_new_project "$task_id")"
  printf -- 'total_open: 1\ntasks:\n  - id: zz00\n    status: done\n    intent: "UNRELATED: x"\n' \
    > "${root}/docs/tasks.yaml"
  _e2e_run "$root" "$task_id"
  if [[ "$E2E_RC" -ne 0 ]] && grep -q "intent-prefix" <<<"$E2E_ERR" \
     && grep -q "no lane-yaml fallback" <<<"$E2E_ERR"; then
    pass "Test 4b: rc!=0, message names id-or-intent-prefix search and that no lane-yaml fallback ran"
  else
    fail "Test 4b: message did not name the search scope, got rc=${E2E_RC}: ${E2E_ERR}"
  fi
}

# ── Test 5: the printed remedy, executed against the fixture, clears the failure ──
test_5_remedy_clears_failure() {
  log "Test 5: leadv2_tasks_release (the printed remedy) executed against a fingerprint fixture clears A2"
  local task_id="E2E-REMEDY-$$" root rc_before
  root="$(_e2e_new_project "$task_id")"
  cat > "${root}/docs/tasks.yaml" <<EOF
total_open: 1
tasks:
  - id: fp-remedy-${RANDOM}
    lane: action
    status: in_progress
    intent: '${task_id}: some milestone description'
    attempts: 0
    max_attempts: 3
EOF
  _e2e_run "$root" "$task_id"
  rc_before="$E2E_RC"
  if [[ "$rc_before" -eq 0 ]]; then
    fail "Test 5: precondition violated -- A2 unexpectedly already PASS before the remedy ran"
    return
  fi
  ( PROJECT_ROOT="$root" bash -c "
      set -e
      source '${TASKS_LIB}'
      leadv2_tasks_release '${task_id}' --outcome success
    " ) >/dev/null 2>&1
  _e2e_run "$root" "$task_id"
  if [[ "$E2E_RC" -eq 0 ]]; then
    pass "Test 5: A2 FAILed before remedy (rc=${rc_before}); leadv2_tasks_release resolved the fingerprint row by intent-prefix; A2 PASSes after (rc=0)"
  else
    fail "Test 5: expected A2 PASS after remedy, got rc=${E2E_RC}: ${E2E_ERR}"
  fi
}

# ── Test 6: syntax checks on every file touched by this fix ────────────────
test_6_syntax() {
  log "Test 6: bash -n / py_compile syntax checks"
  local ok=1
  bash -n "$ASSERT_SH" 2>/dev/null || ok=0
  bash -n "$TASKS_LIB" 2>/dev/null || ok=0
  python3 -m py_compile "$COMMON_PY" 2>/dev/null || ok=0
  if [[ "$ok" -eq 1 ]]; then
    pass "Test 6: leadv2-phase8-assert.sh + leadv2-tasks-lib.sh + leadv2_tasks_yaml_common.py syntax OK"
  else
    fail "Test 6: syntax check failed"
  fi
}

# ── Test M (mutation kill): reverting A2 to an id-only comparison must turn
# THIS suite red on the fingerprint fixture -- proving a control that only
# goes red on an id-equals-name fixture would not have caught the real
# defect. Mutates the real production file on the real call path, checks
# RED, reverts, checks GREEN again. ─────────────────────────────────────────
test_M_mutation_kill_id_only_regression() {
  log "Test M: reverting A2's row lookup to an id-only comparison must go RED on the fingerprint fixture"
  local rc_pre=0 rc_mut=0 rc_post=0

  _run_a2 "V5-M0-SKELETON-01" "$FP_YAML" >/dev/null 2>&1 || rc_pre=$?
  if [[ "$rc_pre" -ne 0 ]]; then
    fail "Test M: baseline not green before mutation (rc=${rc_pre}) -- cannot prove a kill"
    return
  fi

  if ! python3 - "$ASSERT_SH" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    content = f.read()
old = "it = resolve_task(items, task_id)"
new = ("it = None\n"
       "for _cand in items:\n"
       "    if isinstance(_cand, dict) and str(_cand.get(\"id\",\"\")) == task_id:\n"
       "        it = _cand\n"
       "        break")
if content.count(old) != 1:
    sys.exit(1)
content = content.replace(old, new, 1)
with open(path, "w") as f:
    f.write(content)
PYEOF
  then
    fail "Test M: mutation target not found or not unique in ${ASSERT_SH} -- source has drifted"
    cp "$ASSERT_ORIG_BACKUP" "$ASSERT_SH"
    return
  fi

  _run_a2 "V5-M0-SKELETON-01" "$FP_YAML" >/dev/null 2>&1 || rc_mut=$?

  # Revert before evaluating, so a failed assertion below still leaves the
  # production file clean (the exit trap is only the backstop).
  cp "$ASSERT_ORIG_BACKUP" "$ASSERT_SH"

  _run_a2 "V5-M0-SKELETON-01" "$FP_YAML" >/dev/null 2>&1 || rc_post=$?

  if [[ "$rc_mut" -eq 2 && "$rc_post" -eq 0 ]]; then
    pass "Test M: id-only mutation -> RED (rc=2, not-found) on the fingerprint fixture; revert -> GREEN (rc=0) again"
  else
    fail "Test M: expected RED(2)/GREEN(0), got mutated_rc=${rc_mut} reverted_rc=${rc_post}"
  fi
}

main() {
  log "=== GATE-A2-ID-SCHEME-MISMATCH-01 regression tests (RUN_ID=${RUN_ID}) ==="
  log "Script: $ASSERT_SH"
  echo ""
  test_6_syntax
  test_1_fingerprint_intent_prefix_pass
  test_2_id_equals_still_passes
  test_3_no_prefix_bleed_both_directions
  test_4_absent_task_fails
  test_4b_e2e_absent_message_names_search
  test_5_remedy_clears_failure
  test_M_mutation_kill_id_only_regression
  echo ""
  log "=== Results: PASS=$PASS FAIL=$FAIL ==="
  if [[ "${#ERRORS[@]}" -gt 0 ]]; then
    log "Failures:"
    for e in "${ERRORS[@]}"; do log "  $e"; done
    exit 1
  fi
  log "All tests passed."
  exit 0
}

main "$@"
