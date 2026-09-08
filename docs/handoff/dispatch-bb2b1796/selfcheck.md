# builder selfcheck — dispatch-bb2b1796
generated_at: 2026-09-07T23:10:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/bb2b1796
diff_hash: f33b402bc8b31fa343775ed218a009ade5addc14b9bec24b4bef3a5c4bc93066
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-helpers.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-diff-counts-committed-work.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/bb2b1796/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-diff-counts-committed-work.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
