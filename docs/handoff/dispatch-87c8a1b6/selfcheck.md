# builder selfcheck — dispatch-87c8a1b6
generated_at: 2026-09-01T16:56:36Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ONE-LANE-WATCH-01
diff_hash: 9230911ba699e4119d726d95f3e33e480c78229d68a6961bcaacf079c9ba078e
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ONE-LANE-WATCH-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
