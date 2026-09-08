# builder selfcheck — dispatch-b442099d
generated_at: 2026-09-08T12:54:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23
diff_hash: cf9f3b5fcd92e0c3d34bd9734aab95b90bc1a3018e831b68309d564560707d7a
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/75cef0fbfd23/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
