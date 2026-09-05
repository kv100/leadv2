# builder selfcheck — dispatch-1b48c732
generated_at: 2026-08-23T14:40:28Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b3d6f3f8
diff_hash: 0e12f5a1ac84b0fd42fc8e1bb667b19c4e9f164dd38f643ba7efcf07dde22f6e
checks: 9   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-red-first-baseline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-parked-worker-resume.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-red-first-baseline.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b3d6f3f8/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-parked-worker-resume.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-red-first-baseline.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
