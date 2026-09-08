# builder selfcheck — dispatch-157a7898
generated_at: 2026-09-08T17:26:09Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A1-CODEX-TIERS-A2
diff_hash: 859dc0936e04276e9be41d5987e2249af8346a406c808fc3e172a03cc8a7316a
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-launch-registry.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A1-CODEX-TIERS-A2/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-tier-model-table.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
