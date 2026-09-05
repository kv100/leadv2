# builder selfcheck — dispatch-e525df4d
generated_at: 2026-09-04T02:04:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01
diff_hash: c72a4aee5d8bfa440ec307d4ea20830eb0de0fe9fef102e1c36607cc0816ee50
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
