# builder selfcheck — dispatch-2909fbb6
generated_at: 2026-08-31T18:09:28Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-BEAT-ABORT-04
diff_hash: 8aa2e2c5181279e642696598bb1a125504621eb13a4eb0de36f2eec3105c25f8
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-BEAT-ABORT-04/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
