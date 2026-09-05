# builder selfcheck — dispatch-2ac4b579
generated_at: 2026-09-01T16:25:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DIES-MID-TEST-01
diff_hash: 9850680af95b24bdf7eec54b85fa11e2678685cf7139d3122bedfb7c8219fc98
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-longrun.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DIES-MID-TEST-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-longrun.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
