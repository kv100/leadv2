# builder selfcheck — dispatch-6280f73a
generated_at: 2026-08-31T01:35:10Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01
diff_hash: 1907b459f86a2bf890bb15448ab5b63edd6158f7380feaf8ab23fbaf5774a3e0
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
