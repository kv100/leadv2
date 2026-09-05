# builder selfcheck — dispatch-2f3034dc
generated_at: 2026-08-28T15:20:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f3034dc
diff_hash: 2e9db3bc0f1256b3c0bf8db32aa827ff826b8c8ba56a7c8e3b2e6165e3d79919
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f3034dc/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
