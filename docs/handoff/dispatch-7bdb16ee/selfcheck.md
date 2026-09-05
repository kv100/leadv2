# builder selfcheck — dispatch-7bdb16ee
generated_at: 2026-08-23T22:27:39Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7bdb16ee
diff_hash: d98dbf2709fdb4a3593b853a03e9c73f4f0c1c1d43b3820c6803d9b0349caf9d
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-task-anchor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-inject-dedup.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7bdb16ee/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-inject-dedup.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
