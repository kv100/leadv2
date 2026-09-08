# builder selfcheck — dispatch-31b4e0e4
generated_at: 2026-09-07T21:31:46Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/31b4e0e4
diff_hash: fd8fd67cae552d676c2941f6ce4a2ddecfbac13ffcde70fa79f35632e84a4079
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-core-offline-scope-changed.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/31b4e0e4/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-core-offline-scope-changed.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
