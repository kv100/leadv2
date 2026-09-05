# builder selfcheck — dispatch-2236d405
generated_at: 2026-09-04T01:09:23Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01
diff_hash: b225118df2a88cce16bfb85f5daf6800751bab83cc5b575d8e27cbe27655d37a
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-DEAD-ARM-LOOKS-LIKE-A-BUSY-ARM-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-freepool-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
