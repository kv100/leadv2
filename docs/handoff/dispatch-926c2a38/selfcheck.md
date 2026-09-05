# builder selfcheck — dispatch-926c2a38
generated_at: 2026-09-03T11:47:44Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-OUTLIVES-ITS-TERMINAL-STATE-01
diff_hash: 8f780f3bfd102eaa9308e78019da751e0f657ef8b887c2ee7d08ad7e24713dde
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-mutation-control.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-dod-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-dod-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-OUTLIVES-ITS-TERMINAL-STATE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worker-dod-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
