# builder selfcheck — dispatch-1ddcfda2
generated_at: 2026-08-27T02:07:44Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg
diff_hash: fee8f80916b5d435d985727eb26bbcdf1c54d39dcdd2617d8178c36d452216b2
checks: 15   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 10 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-context-glossary-close.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-one-copy-drift.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-skill-authoring-reminder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-continuation-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t-core-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-continuation-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t-core-dispatch-ledger.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |

verdict: GREEN
