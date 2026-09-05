# builder selfcheck — dispatch-f5416cf3
generated_at: 2026-09-02T02:41:09Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CACHE-TRUTH-01
diff_hash: b414e8dea78b9be1a27919cfed09eee13ba631343628c2c8ba5c9879d7bee9be
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-cache-truth.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-cache-truth.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CACHE-TRUTH-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-cache-truth.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
