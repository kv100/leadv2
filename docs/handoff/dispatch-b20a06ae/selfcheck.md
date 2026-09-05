# builder selfcheck — dispatch-b20a06ae
generated_at: 2026-09-02T23:46:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WATCHER-LEAK-01
diff_hash: 398ea707e83d07438c785ae315f06363b53d29638405e28734451e52f8f75e76
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WATCHER-LEAK-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
