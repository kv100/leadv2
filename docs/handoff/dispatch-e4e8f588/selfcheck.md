# builder selfcheck — dispatch-e4e8f588
generated_at: 2026-09-04T01:11:16Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D2-E4-RESOLVES-THE-WRONG-DIR-01
diff_hash: e19f14aa7a9ffd5b9eb31a1b4894652ff6cca6c14cbf47b11f98b725d1398098
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D2-E4-RESOLVES-THE-WRONG-DIR-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
