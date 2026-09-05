# builder selfcheck — dispatch-acde19dc
generated_at: 2026-08-28T11:19:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/acde19dc
diff_hash: c39c7c373a3fba509441c0ff2944886b49ccc5d824c268b936bcc4722d5c0064
checks: 22   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 15 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-install.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-gate1-discipline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-body-lost-retry-distinct-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/acde19dc/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-backlog-pump.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-install.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-gate1-discipline.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-review-body-lost-retry-distinct-arm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
