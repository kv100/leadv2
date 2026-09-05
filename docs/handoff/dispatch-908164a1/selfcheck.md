# builder selfcheck — dispatch-908164a1
generated_at: 2026-08-24T16:49:28Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/908164a1
diff_hash: e4bea189d17edf4d96280d5686dcb158e50c742c7cf5ada303400333e21e0775
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-pulse-watch-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-pulse-watch.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/908164a1/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-pulse-watch.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
