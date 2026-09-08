# builder selfcheck — dispatch-f8b18b54
generated_at: 2026-09-07T13:36:32Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1
diff_hash: 39fbf000fdc68334f98888072c828e347d6116c45fd8c111fe99ee4441552610
checks: 11   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-task-judge.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/tests/test-complexity-source-provenance.sh | 0 |
| bash -n | plugins/leadv2/tests/test-judge-complexity-path.sh | 0 |
| bash -n | plugins/leadv2/tests/test-router-v2-capability-fit.sh | 0 |
| bash -n | plugins/leadv2/tests/test-router-v2-shadow-mode.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/F1-ARBITER-SCORING-20260907-step1/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-complexity-source-provenance.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-judge-complexity-path.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-router-v2-capability-fit.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-router-v2-shadow-mode.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
