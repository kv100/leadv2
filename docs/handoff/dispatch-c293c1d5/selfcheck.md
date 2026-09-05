# builder selfcheck — dispatch-c293c1d5
generated_at: 2026-08-31T11:31:57Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/EFFORT-IS-NOT-WIRED-01
diff_hash: 7a6803f608515e93033c60d89f352b2220e48a11b902eb81e067c200ff008e34
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-effort-routing.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/EFFORT-IS-NOT-WIRED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
