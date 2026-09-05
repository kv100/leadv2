# builder selfcheck — dispatch-14d67d3c
generated_at: 2026-09-01T04:44:34Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WATCHER-LIFECYCLE-LEAK-01
diff_hash: 329db95740556f050874844c884ad5ba1d1ef22fef7a98414f6e442c98bb9595
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-t13-slice2.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WATCHER-LIFECYCLE-LEAK-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-t13-slice2.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
