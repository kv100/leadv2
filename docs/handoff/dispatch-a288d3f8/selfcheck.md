# builder selfcheck — dispatch-a288d3f8
generated_at: 2026-09-01T12:57:04Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FORK-STORM-KILLS-HOOKS-01
diff_hash: 2d2210d48e44c5bb0032252ecd801310a6b8bcb3608916a48cf69fc17e3258fc
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FORK-STORM-KILLS-HOOKS-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
