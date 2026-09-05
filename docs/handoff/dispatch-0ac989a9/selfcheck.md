# builder selfcheck — dispatch-0ac989a9
generated_at: 2026-08-29T02:20:07Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0ac989a9
diff_hash: 88836b97a04706f956db6d169de0d85755bde822316c7cc50b2e1263d4dfcdb9
checks: 3   failed: 1   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh | FAIL (off_write_set) |
| bash -n | plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0ac989a9/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh | ADVISORY (no_falsification_marker) |

verdict: RED
