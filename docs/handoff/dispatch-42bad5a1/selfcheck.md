# builder selfcheck — dispatch-42bad5a1
generated_at: 2026-08-31T01:47:14Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01
diff_hash: 6966b56b9e9e59ce6f6c40c7911c82ae969633baf8ec3f5b5fd8fa4199a8572e
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
