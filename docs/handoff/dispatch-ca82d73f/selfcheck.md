# builder selfcheck — dispatch-ca82d73f
generated_at: 2026-08-28T20:12:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ca82d73f
diff_hash: fb2e198ce1e4b88e2505d67c8317809807a9ecec9f4b37a482aed2eeaf54d559
checks: 34   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 21 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-e2e-gate-bypass-hardening.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-install.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-gate1-discipline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-model-select-telemetry.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-body-lost-retry-distinct-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ca82d73f/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-backlog-pump.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-e2e-gate-bypass-hardening.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-install.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-gate1-discipline.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-founder.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-model-select-telemetry.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-review-body-lost-retry-distinct-arm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
