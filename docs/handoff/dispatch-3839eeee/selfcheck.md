# builder selfcheck — dispatch-3839eeee
generated_at: 2026-08-29T16:38:37Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27
diff_hash: 88610b5cc9da2070ada86cac1f29c83a03f24efab206476d2eb30a06acddb8d4
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
