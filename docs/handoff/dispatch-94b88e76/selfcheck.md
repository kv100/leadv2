# builder selfcheck — dispatch-94b88e76
generated_at: 2026-09-07T12:31:52Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1
diff_hash: 26411176f8200cb60faa958833de2e3f54fea6e5b28e86e586fa7b24c3c08cbd
checks: 9   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-task-judge.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/tests/test-complexity-source-provenance.sh | 0 |
| bash -n | plugins/leadv2/tests/test-router-v2-capability-fit.sh | 0 |
| bash -n | plugins/leadv2/tests/test-router-v2-shadow-mode.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-complexity-source-provenance.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-router-v2-capability-fit.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-router-v2-shadow-mode.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
