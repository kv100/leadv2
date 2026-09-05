# builder selfcheck — dispatch-e93d9162
generated_at: 2026-08-20T09:58:58Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e93d9162
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-stop-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e93d9162/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
