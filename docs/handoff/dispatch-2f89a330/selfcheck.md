# builder selfcheck — dispatch-2f89a330
generated_at: 2026-08-28T02:03:05Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f89a330
diff_hash: a0159164e072517b0ca36117172062a95af09df7fc633dde5063852d6bba4440
checks: 17   failed: 2   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 14 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/freepool-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-gate1-prompt.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-gate1-discipline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f89a330/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-backlog-pump.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-model-selector.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-gate1-discipline.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-route-arbiter-symlink-install.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-backlog-pump.sh (falsification proof) (rc=1)
[TEST] === BACKLOG-PUMP-01 + C-1 test suite ===
[TEST] PASS: shape_gate_pass_floor10: real capture clears floor 10 (the regression that never existed)
[TEST] PASS: shape_gate_pass_floor30: tightest binding window still clears 30
[TEST] PASS: shape_gate_refuse_scaled: all binding windows below floor -> refuse
[TEST] PASS: shape_gate_failopen: {} and non-JSON both pass (quota-reader outage never total-outages dispatch)
[TEST] PASS: shape_gate_codex_limit_reached: a provider that says stop is not rescued by a healthy-looking pct
[TEST] PASS: count_lane_from_liveness: a live dispatch lane is counted (active=1, not 0)
[TEST] PASS: count_no_double_after_join: a task joined to a lane is not double-counted
[TEST] PASS: count_ignores_child_lanes: child_of lane rides a parent slot
[TEST] PASS: count_sweeps_stale_reservation: stale reservation swept, not counted
[TEST] FAIL: ceiling_refuses_7th: dispatched= log=
[TEST] FAIL: floor_dispatches_then_refuses: d5=0 r1=0 log1= j=
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2f89a330/plugins/leadv2/scripts/tests/test-backlog-pump.sh: line 452: [[: 0
0: arithmetic syntax error in expression (error token is "0")
[TEST] FAIL: refusal_dedupe_collapses: lines=0
0 count=0 carried= log=
[TEST] FAIL: starved_not_refused_below_floor: log=
[TEST] PASS: kill_switch_off: no dispatch and no queue mutation
[TEST] PASS: tree_mid_conflict: no dispatch while Git has MERGE_HEAD
[TEST] PASS: tree_state_probe_failure: failed Git probe is fail-closed and truthfully labelled
[TEST] FAIL: duplicate_signature_refused: duplicate was not safely returned to queue
[TEST] PASS: judgment_class_excluded: human-needed lane never dispatched
[TEST] FAIL: judgment_class_excluded: opus-arm candidate not properly unclaimed/surfaced
[TEST] PASS: empty_outcome_bounded: 1st empty -> requeued, 2nd consecutive -> parked (never spins forever)
[TEST] FAIL: auto_dispatch: expected dispatch call, log=
[TEST] 
[TEST] === Results: 14 passed, 7 failed ===
[TEST] FAIL: ceiling_refuses_7th: dispatched= log=
[TEST] FAIL: floor_dispatches_then_refuses: d5=0 r1=0 log1= j=
[TEST] FAIL: refusal_dedupe_collapses: lines=0
0 count=0 carried= log=
[TEST] FAIL: starved_not_refused_below_floor: log=
[TEST] FAIL: duplicate_signature_refused: duplicate was not safely returned to queue
[TEST] FAIL: judgment_class_excluded: opus-arm candidate not properly unclaimed/surfaced
[TEST] FAIL: auto_dispatch: expected dispatch call, log=

## raw — plugins/leadv2/scripts/tests/test-gate1-discipline.sh (falsification proof) (rc=1)
FAIL: standard daemon rc=1 (want 2)
FAIL: ledger: {"event": "gate1_decision", "task_id": "T1", "rc": 1, "outcome": "declined"}
PASS: heavy+DRY_RUN: declined on EOF, NOT auto-accepted (rc=1)
PASS: risk=safety_publish_payments+BOT_MODE: NOT auto-accepted (rc=1)
PASS: heavy async: answered go -> accepted (rc=0)
FAIL: ledger2: {"event": "gate1_decision", "task_id": "T4", "rc": 0, "outcome": "answered"}
PASS: heavy async: default/decline -> rc=1 (timeout can never accept)
PASS: gate T6 accepted via async go
PASS: non-empty gate1 sentinel mirrored under dispatch-<sig8>
PASS: gate1 phase recorded under receipt sig8
PASS: assert --pre-build passes after gate1 accept (Phase-4 re-entry admitted)
PASS: cold Standard without records refused (assert rc=3)
SUMMARY: pass=9 fail=3

verdict: RED
