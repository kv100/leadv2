# builder selfcheck — dispatch-456a9264
generated_at: 2026-08-23T22:58:03Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e8c1289f
diff_hash: 371e685602fe46745d4b5c882220dedfa9d7de9b6b322a828849c3b6718a3a19
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-roundcap.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e8c1289f/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-review-roundcap.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
