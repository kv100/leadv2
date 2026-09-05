# builder selfcheck — dispatch-9cefb22b
generated_at: 2026-08-25T00:24:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9cefb22b
diff_hash: e687e560c07f6ae1dea9e8ae0f19d9379aaf8e8c8567f7fb8a3146c51fae5031
checks: 8   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 7 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2-quota-read.py | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9cefb22b/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
