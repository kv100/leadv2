# builder selfcheck — dispatch-d56bf8bc
generated_at: 2026-08-28T18:37:42Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/d56bf8bc
diff_hash: f2a313efaa5ffd0e95d5040b7dc935a2f981c467ac828c1766c3fa197ceb082e
checks: 8   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/d56bf8bc/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
