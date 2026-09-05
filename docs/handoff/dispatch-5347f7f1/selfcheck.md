# builder selfcheck — dispatch-5347f7f1
generated_at: 2026-08-31T10:15:06Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-RUN-LOSES-VERDICTS-01
diff_hash: 316a34f6033317451a076da4dc209b57f96f07bd08a809123f019b11ab962715
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-body-recovery.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-RUN-LOSES-VERDICTS-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-review-body-recovery.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
