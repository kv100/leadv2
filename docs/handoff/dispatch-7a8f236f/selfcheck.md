# builder selfcheck — dispatch-7a8f236f
generated_at: 2026-09-03T00:27:40Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARBITER-ESTIMATES-BLIND-01
diff_hash: 08f89195949697dd792dc8f1f0558afaa91b199ab532fa0f535bd735b82b941b
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-complexity-routing.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ARBITER-ESTIMATES-BLIND-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-complexity-routing.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
