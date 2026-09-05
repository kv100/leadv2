# builder selfcheck — dispatch-e2e9bf0c
generated_at: 2026-09-04T01:49:43Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SALVAGE-MAIN-MOVED-HAS-NO-CASE-01
diff_hash: 194b1e7e025116a99ce09550f93299e4b3753dda4deb0b41ac094dcda0e72f7e
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lane-salvage.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-salvage.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SALVAGE-MAIN-MOVED-HAS-NO-CASE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-salvage.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
