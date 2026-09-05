# builder selfcheck — dispatch-97669e50
generated_at: 2026-09-03T20:34:32Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01
diff_hash: 785ceb0e57486bb5a97496969b2e86415c23982c5d40ef6d6e22b78d4bf9bb3d
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-quota-window-history.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-ratelimit-history-append.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-ratelimit-history-kv-untouched.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-ratelimit-history-seed-idempotent.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/QUOTA-BINDING-WINDOW-IS-NEVER-RECORDED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-ratelimit-probe.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
