# builder selfcheck — dispatch-62ec970a
generated_at: 2026-09-08T18:27:58Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B2-GATE-BUDGET-2
diff_hash: e74e37dab2dc86b9c42f6bb8bc33b5d7e9324be334120c165b291df5e4e0095a
checks: 3   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B2-GATE-BUDGET-2/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
