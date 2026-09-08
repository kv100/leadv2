# builder selfcheck — dispatch-72e5cf0e
generated_at: 2026-09-08T17:23:02Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C1-RETIRE-RSYNC-2
diff_hash: b4df98ad496c062074efb4727add8481ca0bb9f9c508acf1477c4c2877cd7bc0
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-plugin-sync.sh | 0 |
| bash -n | plugins/leadv2/tests/test-plugin-sync-is-link-only.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C1-RETIRE-RSYNC-2/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-plugin-sync-is-link-only.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
