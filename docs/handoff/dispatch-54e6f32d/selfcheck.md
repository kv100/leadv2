# builder selfcheck — dispatch-54e6f32d
generated_at: 2026-09-03T19:37:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01
diff_hash: cc902acda50c356af2b833763e1abdfb1a3f992194fd8c5222cdf49689d68199
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-claude-account-check.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-claude-account-check-org.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-account-check.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-claude-account-check.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
