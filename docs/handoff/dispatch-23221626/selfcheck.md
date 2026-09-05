# builder selfcheck — dispatch-23221626
generated_at: 2026-09-03T19:23:05Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-WRITES-IS-EMPTY-98-PERCENT-01
diff_hash: ccbbae100e2ad3c3532b03407c8d3f2ee53b59945d7af82f5427480b5ef27092
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-writeset-derive.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-WRITES-IS-EMPTY-98-PERCENT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
