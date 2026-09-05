# builder selfcheck — dispatch-20095269
generated_at: 2026-09-02T03:55:04Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/STATUS-CHURN-01
diff_hash: 559f0563f5893c46d0713b2ac882af5231d03f76935feb8bb71218638dc9f42c
checks: 8   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-cache-truth.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-collector.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-status-cache.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-cache-truth.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-churn.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/STATUS-CHURN-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-cache-truth.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-status-churn.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
