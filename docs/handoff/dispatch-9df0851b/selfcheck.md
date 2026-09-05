# builder selfcheck — dispatch-9df0851b
generated_at: 2026-09-04T01:09:49Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01
diff_hash: 91395748e233e3e42d12742081b77e3c254438754adea7260b8872fc0f6f37a6
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ADMISSION-CLASS-FALLS-BACK-TO-LIGHT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
