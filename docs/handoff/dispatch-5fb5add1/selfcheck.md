# builder selfcheck — dispatch-5fb5add1
generated_at: 2026-09-04T00:04:23Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DERIVE-COERCES-GIT-FAILURE-TO-NO-COMMIT-01
diff_hash: 1c90002fceafa878765ebbba66d321133387b5d29d2c7bb8eb6953fb7464ce17
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DERIVE-COERCES-GIT-FAILURE-TO-NO-COMMIT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-reap-funnel-death-proof.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
