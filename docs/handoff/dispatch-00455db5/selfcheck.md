# builder selfcheck — dispatch-00455db5
generated_at: 2026-08-31T19:16:30Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-ORPHAN-FD-04
diff_hash: d1bc91de484697baa307b9b0081012093353ef36ea52dac17af899188b38da17
checks: 20   failed: 2   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase-record.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-assert.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-tasks-lib.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-effort-routing.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2_tasks_yaml_common.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-ORPHAN-FD-04/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | FAIL (test_failed:rc=124) |
| falsification | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | FAIL (test_failed:rc=124) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-effort-routing.sh (falsification proof) (rc=124)
PASS: adversarial-review kind resolves effort=high
PASS: mechanical/docs kind resolves effort=low
PASS: ordinary heavy code build resolves effort=medium
PASS: new yaml-only effort_matrix rule flips the outcome (no script edit)
PASS: unmodified routing.yaml still resolves medium (control for the anti-hardcode case)
FAIL: codex argv=<no argv captured> dispatch_out=Terminated: 15             bash "${LEDGER_BIN}" sweep > /dev/null 2>&1 9>&-
FAIL: sonnet argv=<no argv captured> dispatch_out=Terminated: 15             bash "${LEDGER_BIN}" sweep > /dev/null 2>&1 9>&-

## raw — plugins/leadv2/scripts/tests/test-lane-finished-state.sh (falsification proof) (rc=124)
[TEST] Test 1: live pid + fresh stream -> alive; not an escalation candidate
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-ORPHAN-FD-04/plugins/leadv2/scripts/tests/test-lane-finished-state.sh: line 193: 10732 Killed: 9                  LEADV2_PROJECT_ROOT="$repo" CLAUDE_PROJECT_DIR="$repo" LEADV2_STATE_ROOT="$state" bash "$SNAPSHOT_SH" --json > /dev/null 2>&1
[TEST] FAIL: Test 1: poll 1 exited nonzero
[TEST] Test 2: dead pid + recent commit -> finished, no escalation, placement not refused

verdict: RED
