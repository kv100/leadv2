# builder selfcheck — dispatch-65d12844
generated_at: 2026-09-01T09:38:18Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASS-IS-COMPUTED-NOT-DECLARED-01
diff_hash: fa63edc9d6985c7e9dfe16e99c0a84f50e805eccab1815f1527d86103738f724
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASS-IS-COMPUTED-NOT-DECLARED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-class-cannot-be-downgraded.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
