# builder selfcheck — dispatch-f279d943
generated_at: 2026-09-03T08:37:41Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-OUTLIVES-ITS-TERMINAL-STATE-01
diff_hash: d17a768710b5246687487ea27f47ff52b11b95d3d2b572a13edc2a3902a3b15f
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-OUTLIVES-ITS-TERMINAL-STATE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
