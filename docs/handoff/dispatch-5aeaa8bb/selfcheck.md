# builder selfcheck — dispatch-5aeaa8bb
generated_at: 2026-08-28T19:02:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/5aeaa8bb
diff_hash: 75458106f7b52e3813935ff7dcf37816d53e6e172d77cdc51e6d0e2e3f469c91
checks: 34   failed: 1   skipped: 1

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
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/5aeaa8bb/tests/run-all.sh | SKIP (delegated_to_e2e) |
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
| falsification | plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh (falsification proof) (rc=1)
[TEST] PASS: B1 kill-switch: LEADV2_PULSE_MODE=0 / LEADV2_SINGLE_LEAD_BEAT=0 -> no-op, nothing armed
[TEST] PASS: B2 beat driven: 3 beat(s) while 1 lane live, loop still running
[TEST] PASS: B3 not armed twice: second invocation exited immediately, pidfile still owns pid 42178
[TEST] PASS: B4 stops on empty board: loop exited after consecutive zeros, pidfile removed
[TEST] PASS: B4b re-arm after stop works (pidfile clean, loop re-armed)
[TEST] FAIL: B5 transient zero: loop died on a non-consecutive zero (H3)
[TEST] FAIL: B6 running_stale live: stale lane silenced the beat (H3)
[TEST] PASS: B7 per-root pidfile: both roots armed their own loop (2 pidfiles, shared dir)
test-single-lead-beat-loop: 6 passed, 2 failed

verdict: RED
