# builder selfcheck — dispatch-2a984f18
generated_at: 2026-08-27T02:59:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg
diff_hash: 714d3329ad1665137109038d17083699ceffdd2fec8d44858d725e8f0be134e1
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh | 0 |

verdict: GREEN
