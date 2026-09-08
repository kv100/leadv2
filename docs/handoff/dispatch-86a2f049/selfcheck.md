# builder selfcheck — dispatch-86a2f049
generated_at: 2026-09-08T21:16:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C2-OWNERSHIP-CHECK
diff_hash: 1dbc12cbaea1d86625dee12d1a580af28e0d02ad45c7d002acfc3777a795e77b
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/plugin-scripts-drift-guard.sh | 0 |
| bash -n | plugins/leadv2/tests/test-ownership-check-names-the-copy.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/C2-OWNERSHIP-CHECK/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-ownership-check-names-the-copy.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
