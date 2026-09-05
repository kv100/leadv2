# builder selfcheck — dispatch-3bdeadcc
generated_at: 2026-08-20T09:28:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/eacd0eb5
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-resume.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/eacd0eb5/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
