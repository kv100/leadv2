# builder selfcheck — dispatch-53b2ae6c
generated_at: 2026-08-24T13:23:02Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/53b2ae6c
diff_hash: 7146ebab5ceeab571c25a32a768500fc6439266ed8240860cc58f027641f9e55
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-worktree-cleanup.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/53b2ae6c/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |

verdict: GREEN
