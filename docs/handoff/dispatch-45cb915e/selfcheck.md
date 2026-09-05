# builder selfcheck — dispatch-45cb915e
generated_at: 2026-09-02T14:41:00Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-DOD-GATE-01
diff_hash: 3a4ae8218254011d79c3493e89e4eaecc82442426404cc6920b66035c9432ada
checks: 7   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-mutation-control.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-dod-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-dod-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKER-DOD-GATE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-worker-dod-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
