# builder selfcheck — dispatch-81f3ffbd
generated_at: 2026-08-23T20:58:32Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9341e2eb
diff_hash: 173b638e91bb6b4d60f87ffa960fdb3020aefff77e91a5396b6e73fbed3e9955
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-subsession-context-diet.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9341e2eb/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-subsession-context-diet.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
