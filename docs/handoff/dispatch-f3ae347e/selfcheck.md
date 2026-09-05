# builder selfcheck — dispatch-f3ae347e
generated_at: 2026-08-25T09:49:05Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/16fbe872
diff_hash: b1e556c97730a0979176cabb2c924ffd0e4e6131f7e96112ba67f958f49b30f6
checks: 7   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 6 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/16fbe872/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
