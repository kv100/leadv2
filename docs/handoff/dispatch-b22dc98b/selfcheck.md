# builder selfcheck — dispatch-b22dc98b
generated_at: 2026-08-23T19:56:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b
diff_hash: 9d642cfe59418f538a74ed50adc40fc2b6eeb1e71044b7da960fa7b6d67ff644
checks: 10   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 9 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-compact-trigger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fanout.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-burn-governor.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-burn-governor.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
