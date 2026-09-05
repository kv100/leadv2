# builder selfcheck — dispatch-6b17ca52
generated_at: 2026-08-23T22:56:22Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7bdb16ee
diff_hash: 087d7d16a6bfa21e460ab1a00100464a5f8afcd30d941b7fe06f89f442e6d4df
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-task-anchor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-inject-dedup.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7bdb16ee/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-inject-dedup.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
