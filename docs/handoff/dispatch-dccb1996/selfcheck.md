# builder selfcheck — dispatch-dccb1996
generated_at: 2026-08-27T02:35:14Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg
diff_hash: 2fa962628dc500605e3a0a52876595ec720b9fb4bcfc40f745b8698548b0a976
checks: 10   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 6 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-one-copy-drift.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t-core-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t-core-dispatch-ledger.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |

verdict: GREEN
