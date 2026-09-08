# builder selfcheck — dispatch-c0840827
generated_at: 2026-09-08T09:58:08Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/da195ecf5abc
diff_hash: 9236ee99c97544dfbfdb4e56c505aea37118952978646be1b196e3b5a121014e
checks: 9   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/tests/test-arm-pool-reachability.sh | 0 |
| bash -n | plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh | 0 |
| bash -n | plugins/leadv2/tests/test-unmetered-account-not-penalised.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/da195ecf5abc/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-arm-pool-reachability.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-unmetered-account-not-penalised.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
