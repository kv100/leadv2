# builder selfcheck — dispatch-a0b27c7a
generated_at: 2026-09-04T08:43:15Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01
diff_hash: 82a87d2b64f2496bda001f50297f5cda04bb5a652587435bd8c5c6186d4eb9e7
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-await.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-lane-address.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-await.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MONITORS-ARE-THE-SECOND-CONSUMER-OF-THE-ADDRESS-RESOLVER-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-await.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
