# builder selfcheck — dispatch-cde5e368
generated_at: 2026-09-08T08:54:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ae63fbff
diff_hash: 05695ea6f7f83c81d3b3ee9f7da952e22b4642d31914420e73d365ba777eb081
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-scope-excludes-nested-housekeeping.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ae63fbff/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-scope-excludes-nested-housekeeping.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
