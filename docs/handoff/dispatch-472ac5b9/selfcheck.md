# builder selfcheck — dispatch-472ac5b9
generated_at: 2026-09-03T23:40:32Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D2-UNBLIND-AND-THIRD-STATE-M0M1-01
diff_hash: 3bf00c4e4d8130439699222ac0361ac58def432b4a6628518d90a732aa22c8f6
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D2-UNBLIND-AND-THIRD-STATE-M0M1-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
