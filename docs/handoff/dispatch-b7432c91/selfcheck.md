# builder selfcheck — dispatch-b7432c91
generated_at: 2026-09-03T22:46:44Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01
diff_hash: eb99b680468a1c471d89f75914cfdccb0e761c73cd1448acbc43b4b8618b3bf9
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
