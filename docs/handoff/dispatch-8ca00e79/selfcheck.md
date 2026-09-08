# builder selfcheck — dispatch-8ca00e79
generated_at: 2026-09-07T20:29:39Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/13581c3eb064
diff_hash: 261e0e8747ac7759b25ac47254b818b393a6e7b63a1951d94b830dc045e54524
checks: 8   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 6 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/tests/test-arm-pool-reachability.sh | 0 |
| bash -n | plugins/leadv2/tests/test-exclusion-stages.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/13581c3eb064/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-arm-pool-reachability.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-exclusion-stages.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
