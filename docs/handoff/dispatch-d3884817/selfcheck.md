# builder selfcheck — dispatch-d3884817
generated_at: 2026-09-04T11:22:15Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01
diff_hash: 8054f51d3189b4f57b5ccbdea2d81b9c3c4380b329ab2515023b6ddce8cc16da
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
