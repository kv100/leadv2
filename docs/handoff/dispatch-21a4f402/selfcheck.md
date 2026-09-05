# builder selfcheck — dispatch-21a4f402
generated_at: 2026-08-28T16:41:01Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/21a4f402
diff_hash: d1641df0018b73ce980ef7fe693c3414c62db0850c0dbe6d7fdffc406bacdf09
checks: 9   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 6 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/21a4f402/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
