# builder selfcheck — dispatch-a92a706e
generated_at: 2026-09-03T18:48:32Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01
diff_hash: 6d1c87949d36da6b497f4c0f7463ec3e943d7340ea4b89eb98e03cbe5aaa1c39
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-repo-install.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-settings-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| bash -n | tests/test-installer-settings-guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | tests/test-installer-settings-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
