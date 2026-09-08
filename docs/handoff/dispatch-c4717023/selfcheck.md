# builder selfcheck — dispatch-c4717023
generated_at: 2026-09-08T17:02:05Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/60fdbb5be2c6
diff_hash: d8c76b65f43ec97c023cdad6f227a5ce7fab8f03d5d5791a4488878c27b2d1c1
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/tests/test-401-is-not-a-dead-account.sh | 0 |
| bash -n | plugins/leadv2/tests/test-claude-account-states.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2-quota-read.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/60fdbb5be2c6/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-401-is-not-a-dead-account.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-claude-account-states.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
