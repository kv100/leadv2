# builder selfcheck — dispatch-92411019
generated_at: 2026-09-04T19:38:23Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WRITESET-PENDING-BLOCKS-WITHOUT-ANY-OVERLAP-01
diff_hash: d6f8c9a9e078fe26b88994ac65c4db2133e125bb01ccc00da9b265200934519c
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-helpers.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-writeset-pending-overlap.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WRITESET-PENDING-BLOCKS-WITHOUT-ANY-OVERLAP-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-writeset-pending-overlap.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
