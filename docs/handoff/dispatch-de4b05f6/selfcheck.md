# builder selfcheck — dispatch-de4b05f6
generated_at: 2026-09-08T18:51:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A1-CODEX-TIERS-A3
diff_hash: 6de530beed51e403300020194ffb5f6258db9ab53aa95ba952c72a0623654688
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-launch-registry.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A1-CODEX-TIERS-A3/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
