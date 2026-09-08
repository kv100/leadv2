# builder selfcheck — dispatch-6fcc1dc8
generated_at: 2026-09-07T09:26:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1
diff_hash: ea4c89b03b59279a73ce485c4a7b9954f42ed141d6f53b47f7063ff6cff9489c
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/tests/test-router-v2-capability-fit.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-router-v2-capability-fit.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
