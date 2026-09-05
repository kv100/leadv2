# builder selfcheck — dispatch-e8c1289f
generated_at: 2026-08-23T22:36:06Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e8c1289f
diff_hash: 5e4afc034f622a801905785eb6717fe2d75f29352f0746dc45dd25399da242c4
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-roundcap.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e8c1289f/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-review-roundcap.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
