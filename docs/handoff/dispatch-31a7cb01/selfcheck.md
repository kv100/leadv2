# builder selfcheck — dispatch-31a7cb01
generated_at: 2026-09-04T03:52:19Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INVISIBLE-DELIVERABLES-CENSUS-01
diff_hash: 5bb07cebc04b18673118a168e28c88a2e8f27db402eeed5a8bfe0eb53fa1899f
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-report.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-recovery-context.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-lane-address.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-report-address.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INVISIBLE-DELIVERABLES-CENSUS-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-report-address.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
