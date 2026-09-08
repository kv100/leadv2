# builder selfcheck — dispatch-c3aeb642
generated_at: 2026-09-08T19:05:10Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C1-RETIRE-RSYNC-3
diff_hash: 0a9e3d3fa6540bf84a8b40af687fc5fcff07f21d71b01d947f0e36be2b8a83a8
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-plugin-sync.sh | 0 |
| bash -n | plugins/leadv2/tests/test-plugin-sync-is-link-only.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C1-RETIRE-RSYNC-3/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-plugin-sync-is-link-only.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
