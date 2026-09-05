# builder selfcheck — dispatch-99fe4e58
generated_at: 2026-08-23T06:46:26Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849
diff_hash: 17afad8266b0d47c0b232fa64dfe260474bb575c9ed62e359786f8a2f58e176a
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
