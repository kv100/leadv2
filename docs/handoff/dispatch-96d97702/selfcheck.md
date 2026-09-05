# builder selfcheck — dispatch-96d97702
generated_at: 2026-09-04T15:29:36Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01
diff_hash: 34a7bb126ec324c0379a092cec5e890e3d1548d8e51125dac4a69e62619b461c
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase8-closes-the-backlog-row.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BACKLOG-ONLY-GROWS-CLOSING-IS-MANUAL-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase8-closes-the-backlog-row.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
