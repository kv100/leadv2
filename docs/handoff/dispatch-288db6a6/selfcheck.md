# builder selfcheck — dispatch-288db6a6
generated_at: 2026-08-29T02:21:16Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/288db6a6
diff_hash: 709821936b4850fd9cb41c972b5cd91144a7986c87f9c5811f455f32616deb73
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/288db6a6/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
