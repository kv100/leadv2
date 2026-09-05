# builder selfcheck — dispatch-15a3abee
generated_at: 2026-09-04T01:09:41Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-SALVAGE-TOOL-01
diff_hash: 78a2ab89ef680365ab56633f3a488f5997efd38879a9a743bfd2fd9a3fcaf568
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-salvage.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-salvage.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-SALVAGE-TOOL-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-salvage.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
