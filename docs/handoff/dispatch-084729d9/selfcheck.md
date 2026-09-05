# builder selfcheck — dispatch-084729d9
generated_at: 2026-08-20T13:12:56Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b4042501
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b4042501/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
