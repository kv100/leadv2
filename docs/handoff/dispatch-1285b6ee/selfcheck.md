# builder selfcheck — dispatch-1285b6ee
generated_at: 2026-09-08T05:23:13Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/4b5b0efd
diff_hash: 359f6d692fdec4b2e35428608ab1ae125c0e6159a9b784e6391cfaffee360b71
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/4b5b0efd/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-gate-reaches-a-verdict.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
