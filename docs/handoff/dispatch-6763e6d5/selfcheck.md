# builder selfcheck — dispatch-6763e6d5
generated_at: 2026-09-08T11:08:43Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b0fe5f28527e
diff_hash: b70ad5f21965717041d3f7968276caf24c37ba308e63fac5f1b1e9df8fe9ebf0
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b0fe5f28527e/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
