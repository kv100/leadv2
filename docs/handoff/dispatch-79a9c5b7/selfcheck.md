# builder selfcheck — dispatch-79a9c5b7
generated_at: 2026-09-03T19:43:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01
diff_hash: b7ecf9fe32a2c3ae1653df926a2f6362268191288e65cba7d017dacac33ba348
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-quota-reset-unknown-window-name.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-quota-reset-unreadable-reset-zero.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-quota-reset-wait-predicate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-quota-reset-arbiter.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
