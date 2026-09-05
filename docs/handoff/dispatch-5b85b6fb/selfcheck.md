# builder selfcheck — dispatch-5b85b6fb
generated_at: 2026-08-21T01:07:53Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/04789baf
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-instant-complete.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-machine-round0.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/04789baf/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
