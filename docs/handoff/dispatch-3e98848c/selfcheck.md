# builder selfcheck — dispatch-3e98848c
generated_at: 2026-08-31T16:03:17Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-LIVENESS-PROVE-03
diff_hash: 63064bc0ed794d6a96ce8590ae9f5579e8ff5fa8b5fa0b21e829d80bf6931b5f
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-LIVENESS-PROVE-03/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
