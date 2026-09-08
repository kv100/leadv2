# builder selfcheck — dispatch-9c057339
generated_at: 2026-09-08T16:32:47Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A4-WIRE-ESTIMATOR
diff_hash: 0c19741353e8eb39e9ed6215c7f35b73566b85f4a221664536ed7398f8b2f19c
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-depth-gate-uses-the-estimate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/A4-WIRE-ESTIMATOR/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-depth-gate-uses-the-estimate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
