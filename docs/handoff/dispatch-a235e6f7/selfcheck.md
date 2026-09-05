# builder selfcheck — dispatch-a235e6f7
generated_at: 2026-08-27T01:39:09Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg
diff_hash: e61e466f7e0792fe7d530bce87cd1beed696a5407f731be8c41832ae2e80bc1d
checks: 9   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 7 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-one-copy-drift.sh | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/hooks/leadv2-plugin-sync-drift-warn.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-shared-script-warn.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-worktree.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-worktree-resurrect-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-worktree-resurrect-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
