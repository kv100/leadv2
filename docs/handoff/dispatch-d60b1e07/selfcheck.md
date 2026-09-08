# builder selfcheck — dispatch-d60b1e07
generated_at: 2026-09-08T12:00:17Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
diff_hash: aae7c3e62bd55e32e420a2c0cf72fb5facc08db488e4c783350f83640ea27a6a
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
