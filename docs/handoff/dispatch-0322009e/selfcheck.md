# builder selfcheck — dispatch-0322009e
generated_at: 2026-08-23T04:38:57Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/273da7e9
diff_hash: 66119e4830867a9e54b3c86151c37b7af010ceec269120d264effe21d90bb7a1
checks: 10   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-state-path-migration.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/273da7e9/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-state-path-migration.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh | 0 |

verdict: GREEN
