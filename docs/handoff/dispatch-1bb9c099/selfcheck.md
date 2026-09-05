# builder selfcheck — dispatch-1bb9c099
generated_at: 2026-08-23T14:00:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/67198a6e
diff_hash: 4c36709bee32b39cf7f4536c615e5c765563b76dc8ecefc63ae8b207189009d9
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-plugin-sync.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/67198a6e/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
