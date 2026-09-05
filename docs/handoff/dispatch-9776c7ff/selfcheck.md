# builder selfcheck — dispatch-9776c7ff
generated_at: 2026-08-31T14:48:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01
diff_hash: bb2ce54ed953fef980a222acce3f00af9e71c614cf58e0b451282e50f7fc92e2
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-assert.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-tasks-lib.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2_tasks_yaml_common.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase8-a2-id-resolution.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
