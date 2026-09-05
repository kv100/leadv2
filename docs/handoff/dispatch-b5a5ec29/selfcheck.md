# builder selfcheck — dispatch-b5a5ec29
generated_at: 2026-08-23T11:03:27Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849
diff_hash: 76857c0d1c2a842215a96563979bbc497b8ea8723930651ef2102d70bc82f2cd
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2d8a2849/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
