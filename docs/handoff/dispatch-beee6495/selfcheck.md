# builder selfcheck — dispatch-beee6495
generated_at: 2026-09-03T19:26:18Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITES-MUTATE-LIVE-CONTROL-PLANE-01
diff_hash: f8a0a3709121b9dafe1057c469d9478c6a607183112cdcc86190eb518abee9c1
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITES-MUTATE-LIVE-CONTROL-PLANE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
