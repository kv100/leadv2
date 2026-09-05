# builder selfcheck — dispatch-04789baf
generated_at: 2026-08-20T21:37:41Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/04789baf
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-event.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-machine-round0.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/04789baf/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
