# builder selfcheck — dispatch-e3cec9b5
generated_at: 2026-09-04T01:12:23Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HANDOFF-ARTIFACTS-ALLOWLIST-IS-NAME-BASED-01
diff_hash: 3d56d9f4b66dbea7a20f53bcd0c81b149929c5c696b4814dd6a548ba693969d2
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HANDOFF-ARTIFACTS-ALLOWLIST-IS-NAME-BASED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-handoff-artifacts-tracked.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
