# builder selfcheck — dispatch-ad6c545c
generated_at: 2026-09-01T22:26:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GLM-ARM-THROUGHPUT-01
diff_hash: c01aa884a4bbf1f62a38390863d434442598e353014d8b9fd70cdb31b203c936
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-glm-flash-handle.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GLM-ARM-THROUGHPUT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-glm-flash-handle.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
