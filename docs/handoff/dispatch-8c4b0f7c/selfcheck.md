# builder selfcheck — dispatch-8c4b0f7c
generated_at: 2026-08-30T10:14:46Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02
diff_hash: 8803631fa455e730fa1ff42aebced0a59bfbe244fdc61c52536eb81619d37b57
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-ROWS-02/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
