# builder selfcheck — dispatch-4a82f993
generated_at: 2026-08-25T12:32:41Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/db9a8aa8
diff_hash: c0034d1a6c58a31f8ad48ee1ba6f2592d6d1a0a8fc5e10f2a9fea605a16fdf0e
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-reason.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/db9a8aa8/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
