# builder selfcheck — dispatch-27f745a4
generated_at: 2026-09-07T11:16:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1
diff_hash: ff7710017896312ef6df711b09cd73d6b737f374f826e2345c22e43d2c02583c
checks: 7   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-task-judge.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/tests/test-complexity-source-provenance.sh | 0 |
| bash -n | plugins/leadv2/tests/test-router-v2-capability-fit.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-complexity-source-provenance.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-router-v2-capability-fit.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
