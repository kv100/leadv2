# builder selfcheck — dispatch-21254be3
generated_at: 2026-09-02T14:01:39Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DRIFT-GUARDS-TO-CANON-01
diff_hash: 5f23d9ed5a7c497303e05afa0f1bf95275d329c4ae511fa1a3afae3095bee4d9
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/plugin-scripts-drift-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-scripts-drift-guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DRIFT-GUARDS-TO-CANON-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-scripts-drift-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
