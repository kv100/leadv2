# builder selfcheck — dispatch-98dee5df
generated_at: 2026-09-03T10:22:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01
diff_hash: 4207d046cb99b098bbee58aa202da5e179e07f1bfd9487d73df50d1c7ad05cd4
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
