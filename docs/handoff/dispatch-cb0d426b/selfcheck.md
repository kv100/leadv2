# builder selfcheck — dispatch-cb0d426b
generated_at: 2026-09-04T05:41:31Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LAND-PATH-IS-BROKEN-01
diff_hash: ef2d71a41857dc98fe67f64a6641a4156e3db110be4b532d896482ef9589ca50
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-land.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-land.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LAND-PATH-IS-BROKEN-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-land.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
