# builder selfcheck — dispatch-e1836bd3
generated_at: 2026-09-08T08:39:40Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6a9b3aaa
diff_hash: 3063b017ae8e6849087324f014ce048442f8354fd833dcfcc4d7ccd825bdbdab
checks: 3   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | tests/test-status-surface-single-lead.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/6a9b3aaa/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | tests/test-status-surface-single-lead.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
