# builder selfcheck — dispatch-b39bc839
generated_at: 2026-08-31T11:00:13Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARMS-ADMISSION-01
diff_hash: 8f8eb50b56de0a76bf3a3622f6ef7cf1cd67cda729384e835fe6586dafc8c41d
checks: 2   failed: 0   skipped: 4

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| resolve | plugins/leadv2/scripts/docs/leadv2/.bus-offsets | SKIP (unresolved_path) |
| resolve | plugins/leadv2/scripts/docs/leadv2/questions | SKIP (unresolved_path) |
| bash -n | plugins/leadv2/scripts/tests/test-arm-admission.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARMS-ADMISSION-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-arm-admission.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
