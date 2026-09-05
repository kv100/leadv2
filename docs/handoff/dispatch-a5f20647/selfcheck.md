# builder selfcheck — dispatch-a5f20647
generated_at: 2026-09-03T17:53:51Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INSTALLER-REFUSAL-URGENT-01
diff_hash: ba3311d8534fda8bea24287531e17c8e50d3a5221fe9adf58f13e23674b15463
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-repo-install.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-lane-state.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INSTALLER-REFUSAL-URGENT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
