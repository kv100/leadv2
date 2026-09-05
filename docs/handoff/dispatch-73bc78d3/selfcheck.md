# builder selfcheck — dispatch-73bc78d3
generated_at: 2026-08-31T01:36:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01
diff_hash: 1f1694b967df475b339d3fbad0a4a9f46ac616f586d0b957687446b79572ca8a
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-status-surface.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
