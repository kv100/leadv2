# builder selfcheck — dispatch-db335a0d
generated_at: 2026-08-27T04:14:44Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t12prof
diff_hash: b1a8c4d7ec30a06dba70be37abc9f538d971ca506f11d49430f37c5c24459fb8
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t12prof/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
