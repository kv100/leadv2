# f95b50a3 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/f95b50a3` before worktree removal
(LEADV2-WORKTREE-CLEANUP-20260907). The branch's own committed content is a
stale Aug-29 snapshot (dispatch-code.sh 7192 lines vs main's 9310; active.yaml
still a regular file, pre-dating the symlink-to-leadv2-state migration) --
safe to discard, main strictly newer on every other touched file.

This one untracked file could not be classified with confidence and is
preserved rather than deleted, per the "file name matches a real concept,
stop and check" rule: `phase_precondition_refused` (the string this test
asserts on) still exists in main's leadv2-dispatch-code.sh today, so the
mechanism it tests is not dead -- but the test's CLI usage pre-dates
significant dispatch-code.sh growth (2100+ lines added since), and its
`--task-class ""` / `--protected 0` / `--kind code` invocation shape was not
verified against the current CLI contract. Restoring this is a deliberate
act by whoever owns the row, not an automatic land.

## `plugins/leadv2/scripts/tests/test-phase-integrity-01.sh` (untracked, 143 lines)

Text only — nothing here is installed or made executable. Restoring it is a
deliberate act by whoever owns the row.

```bash
#!/usr/bin/env bash
# test-phase-integrity-01.sh — test for PHASE-INTEGRITY-01 requirements
# Tests that unclassified tasks are refused and phase proofs are machine-attributable

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_CODE="${SCRIPT_DIR}/../leadv2-dispatch-code.sh"
PHASE_RECORD="${SCRIPT_DIR}/../leadv2-phase-record.sh"

# Use a temp project root
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export LEADV2_PROJECT_ROOT="$TMP_ROOT"
export LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/.cache"
export LEADV2_JOURNAL_BIN=/dev/null  # silent — no real journal
export LEADV2_REQUIRE_PHASES=1  # Enable phase checking (refuse mode)

# Create basic directory structure
mkdir -p "${TMP_ROOT}/docs/handoff"
mkdir -p "${TMP_ROOT}/src"
echo "print('hello')" > "${TMP_ROOT}/src/main.py"

# Test 1: Unclassified task should be refused
printf 'test: unclassified task refused\n'
MISSION_TEXT="print('hello world')"

# Dispatch with no task class (should refuse)
OUTPUT="$("${DISPATCH_CODE}" "${MISSION_TEXT}" --task-class "" --kind code --protected 0 2>&1)"; RC=$?

if [[ $RC -eq 3 ]] && [[ "$OUTPUT" == *"phase_precondition_refused reason=missing_task_class"* ]]; then
  echo "  PASS: Unclassified task correctly refused"
else
  echo "  FAIL: Expected rc=3 and 'phase_precondition_refused reason=missing_task_class'"
  echo "  Got: rc=$RC, output='$OUTPUT'"
  exit 1
fi

# Test 2: Classified task should proceed to phase checking
printf 'test: classified task proceeds to phase checking\n'
MISSION_TEXT="print('hello world')"

# Dispatch with a task class but no plan artifact (should fail on plan phase)
OUTPUT="$("${DISPATCH_CODE}" "${MISSION_TEXT}" --task-class "Standard" --kind code --protected 0 2>&1)"; RC=$?

if [[ $RC -eq 3 ]] && [[ "$OUTPUT" == *"missing=plan"* ]]; then
  echo "  PASS: Classified task proceeds to phase checking and fails on missing plan"
else
  echo "  FAIL: Expected rc=3 and 'missing=plan'"
  echo "  Got: rc=$RC, output='$OUTPUT'"
  exit 1
fi

# Test 3: Hand-written context.yaml should not satisfy plan phase
printf 'test: hand-written context.yaml does not satisfy plan phase\n'
MISSION_TEXT="print('hello world')"

# Create a hand-written context.yaml (simulating the bypass)
HANDOFF_DIR="${TMP_ROOT}/docs/handoff/dispatch-deadbeef"
mkdir -p "${HANDOFF_DIR}"
cat > "${HANDOFF_DIR}/context.yaml" <<EOF
id: dispatch-deadbeef
mission: |
  print('hello world')
reads: []
writes: [src/main.py]
lane_writes: [src/main.py]
acceptance:
  authored_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
decisions:
  - Test decision
off_limits: []
plan:
  steps:
    - print('hello')
EOF

# Record the hand-written context as done (simulating the lead's bypass)
"${PHASE_RECORD}" record "deadbeef" plan --status done \
  --artifact context.yaml --owner test:test 2>/dev/null

# Now try to dispatch - should fail because plan proof is not machine-attributable
OUTPUT="$("${DISPATCH_CODE}" "${MISSION_TEXT}" --task-class "Standard" --kind code --protected 0 2>&1 || true)"
RC=$?

if [[ $RC -eq 3 ]] && [[ "$OUTPUT" == *"missing=plan"* ]]; then
  echo "  PASS: Hand-written context.yaml does not satisfy plan phase"
else
  echo "  FAIL: Expected rc=3 and 'missing=plan' (plan proof should not be attributable)"
  echo "  Got: rc=$RC, output='$OUTPUT'"
  exit 1
fi

# Test 4: Properly generated plan artifact should work
printf 'test: properly generated plan artifact satisfies plan phase\n'
MISSION_TEXT="print('hello world')"

# Create a proper context.yaml via leadv2-plan-run (simulating a real planner run)
# For this test, we'll simulate by creating a context.yaml that would pass validation
HANDOFF_DIR="${TMP_ROOT}/docs/handoff/dispatch-facecafe"
mkdir -p "${HANDOFF_DIR}"
cat > "${HANDOFF_DIR}/context.yaml" <<EOF
id: dispatch-facecafe
mission: |
  print('hello world')
reads: []
writes: [src/main.py]
lane_writes: [src/main.py]
acceptance:
  authored_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
decisions:
  - Test decision
off_limits: []
plan:
  steps:
    - print('hello')
EOF

# But we need to simulate that this came from a real planner run.
# In the actual implementation, this would be verified by checking
# that the planner actually ran (via journal or similar).
# For now, let's test that at least the artifact exists and has the right structure.

# Record this as if it came from a real planner (we'll bypass the machine-attributability
# check for this test since we're focusing on the unclassified task requirement)
"${PHASE_RECORD}" record "facecafe" plan --status done \
  --artifact context.yaml --owner test:test 2>/dev/null

# Now dispatch should proceed past the plan phase (might fail on later phases)
OUTPUT="$("${DISPATCH_CODE}" "${MISSION_TEXT}" --class "Standard" --kind code --protected 0 2>&1 || true)"
RC=$?

# Should not fail on plan phase specifically (might fail on gate1, build, etc.)
if [[ "$OUTPUT" != *"missing=plan"* ]]; then
  echo "  PASS: Properly generated plan artifact satisfies plan phase"
else
  echo "  FAIL: Expected plan phase to pass"
  echo "  Got: output='$OUTPUT'"
  exit 1
fi

echo "[PHASE-INTEGRITY-01] All tests passed"
exit 0
```
