# builder selfcheck — dispatch-c10b4c4e
generated_at: 2026-08-24T13:11:19Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/53b2ae6c
diff_hash: 76bace925ee85157d79ec389153f9f6e341570fdfffefbee7af357c4891ccd44
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 6 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-orphan-monitor-sweep.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/53b2ae6c/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |

verdict: GREEN
