# builder selfcheck — dispatch-ab933592
generated_at: 2026-09-04T05:04:14Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01
diff_hash: 18220dc7cab856d59a026b68f0c205d78dbcb0c489407c8b65f08fb0076fe659
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-budget-check.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-STREAM-IS-OVERWRITTEN-BY-THE-NEXT-ATTEMPT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
