# builder selfcheck — dispatch-83645a5a
generated_at: 2026-08-31T15:22:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-LIVENESS-THREE-STATES-02
diff_hash: 3d1d1baa9ced60458c8ef49ffabd71e56e419dd9ca43f58ed85a8639febedfe2
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-LIVENESS-THREE-STATES-02/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
