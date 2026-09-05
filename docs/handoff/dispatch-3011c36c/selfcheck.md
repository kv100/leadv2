# builder selfcheck — dispatch-3011c36c
generated_at: 2026-09-04T02:29:34Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01
diff_hash: 7f61701410781860f699f50fc76a9d96a7a186fb2f0b9037db6b0a615df25ded
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-roundcap.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-review-roundcap.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
