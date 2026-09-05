# builder selfcheck — dispatch-be70b3f8
generated_at: 2026-08-23T03:14:18Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/be70b3f8
diff_hash: ec1b54e1e7c2d6e8ee304ad55e540b3373596845efea4142d2159de7cad82f6a
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/be70b3f8/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh | 0 |

verdict: GREEN
