# builder selfcheck — dispatch-815e62ea
generated_at: 2026-08-31T09:36:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-ORIGIN-MAIN-01
diff_hash: dfa538a4b7844c6fa5ae0af12ddd18c2952a08801bd981268a3a9bca98581c5d
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-ORIGIN-MAIN-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worker-gate-no-origin.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
