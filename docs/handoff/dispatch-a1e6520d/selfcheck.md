# builder selfcheck — dispatch-a1e6520d
generated_at: 2026-09-03T18:51:47Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SKILL-USAGE-IS-UNMEASURED-01
diff_hash: e222c885a1d0de4d69e5807358e38d3cc70b6f757fa60eefab4ac522c0606175
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-skill-rollup.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-skill-usage-tally.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-skill-telemetry.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SKILL-USAGE-IS-UNMEASURED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-skill-telemetry.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
