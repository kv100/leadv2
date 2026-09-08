# builder selfcheck — dispatch-fb9df7f1
generated_at: 2026-09-07T20:19:08Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/d2823c51e670
diff_hash: 0456096b0cdb6712f0d956a44f9404ee847f1795164719c733ee59a8f9e6f161
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-arm-receipts-import.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-arm-receipts.sh | 0 |
| bash -n | plugins/leadv2/tests/test-arm-receipt-identity.sh | 0 |
| bash -n | plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/d2823c51e670/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-arm-receipt-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
