# builder selfcheck — dispatch-60ec85a4
generated_at: 2026-08-28T17:37:32Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/60ec85a4
diff_hash: 1f1da6a812211fa78dcece8727be91ed57046421443e8cbfc569903e06316e3e
checks: 12   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 8 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/60ec85a4/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
