# builder selfcheck — dispatch-8799bc93
generated_at: 2026-09-01T20:36:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-TURN-IT-ON-01
diff_hash: 06ba2aa694f926a75b6118fea17949809a7f1c4fd1361e5fa415d882e9d701b7
checks: 91   failed: 3   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/leadv2-hook-fork-budget.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/lib/leadv2-guard-verdict.sh | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-guard-census.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase-record.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-pulse-beat.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-repo-install.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-suite-falsifiable.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-lane-state.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-sleep.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-watch-lifecycle.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/fixtures/fx-always-block.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/fixtures/fx-disabled.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/fixtures/fx-hang.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/fixtures/fx-logonly.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/fixtures/fx-silent.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-always-block.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-disabled.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-hang.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-logonly.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-nofix.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-quiet.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-silent.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/hook-dir/fx-unwired.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/real/leadv2-block-bash-heredoc.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/real/leadv2-idle-lead-guard.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/real/leadv2-lead-edit-guard.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/real/leadv2-promise-guard.fixture.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-longrun.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-effort-routing.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-guard-census.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-hook-fork-budget.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-model-select-telemetry.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-record.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-papercuts.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-repo-scoped.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t13-slice2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-watch-lifecycle.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-TURN-IT-ON-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-codex-longrun.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | FAIL (test_failed:rc=4) |
| falsification | plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-guard-census.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-hook-fork-budget.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-model-select-telemetry.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-phase-record.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-papercuts.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-status-repo-scoped.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t13-slice2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-watch-lifecycle.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-effort-routing.sh (falsification proof) (rc=4)
PASS: adversarial-review kind resolves effort=high
PASS: mechanical/docs kind resolves effort=low
PASS: ordinary heavy code build resolves effort=medium
PASS: new yaml-only effort_matrix rule flips the outcome (no script edit)
PASS: unmodified routing.yaml still resolves medium (control for the anti-hardcode case)
PASS: codex arm receives --effort high in its own launch args (distinct from --tier)
PASS: sonnet arm receives --effort in its own launch args, no --tier flag (different shape than codex)

## raw — plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh (falsification proof) (rc=1)
PASS: bash syntax: arbiter + dispatch
FAIL: (b) standard build: freepool selected despite capability floor (arm=freepool model=freepool-default tier=standard effort=medium reason=cheapest_capable chain=freepool,codex,sonnet util_glm=99 util_codex=20 util_claude=20 util_freepool=0 floor_mode=full floor_mode_source=yaml complexity=unknown duration_class=unknown) -- 
FAIL: (b) standard build: floor line missing (arm=freepool model=freepool-default tier=standard effort=medium reason=cheapest_capable chain=freepool,codex,sonnet util_glm=99 util_codex=20 util_claude=20 util_freepool=0 floor_mode=full floor_mode_source=yaml complexity=unknown duration_class=unknown) -- 
FAIL: (b) standard build: freepool not last in chain (freepool,codex,sonnet) -- 
FAIL: (b) standard build: codex/sonnet do not both rank ahead (freepool,codex,sonnet) -- 
FAIL: (b) state file: missing task stamp or floor fields ({"arm": "freepool", "task": "deadbeef", "floor_applied": false, "floor_reason": ""}) -- 
PASS: (b2) heavy build: freepool not selected
PASS: (b2) strategic build: freepool not selected
PASS: (c) bulk build: freepool still selectable
PASS: (c) bulk build: no floor token for bulk
PASS: (c2) trivial build: freepool still selectable (floor keys on raw class)
PASS: (c2) light build: freepool still selectable (floor keys on raw class)
PASS: (c3) standard docs: freepool still selectable (floor is build-only)
FAIL: (dispatch) arm_floor_applied journal line missing (log: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//fp08-floor.BO1k0r/dispatch-out.log) -- 
FAIL: (dispatch) route_resolved picked freepool for a standard build (selection outcome) -- 
PASS: (a) bulk build resolved to freepool
PASS: (a) waiter did not declare no_work early (worker finishes at t+8s, window is 3s)
PASS: (a) freepool run finalized complete after the window
PASS: (a) run left a REAL diff on disk (diff.patch with hunks)
PASS: (negative-control) floor mutation applied to a throwaway arbiter copy
PASS: (negative-control) with the floor removed, (b) runs RED: freepool WINS the standard build and the floor token vanishes
PASS: (e1) env full: freepool WINS the standard build (inverse of (b))
PASS: (e1) env full: no floor token in full mode
PASS: (e1) env full: floor_mode=full floor_mode_source=env tokens present
PASS: (e2) yaml full: freepool WINS the standard build
PASS: (e2) yaml full: floor_mode=full floor_mode_source=yaml tokens present
PASS: (e3) garbage env falls through to the yaml key (bulk_only, source=yaml)
PASS: (e3) no env + no yaml key: default bulk_only, source=default
PASS: (e4) freepool_floor_mode mode=full source=env journaled by the dispatcher
PASS: (e4) floor mode full: route_resolved PICKS freepool for a standard build
FAIL: (e4b) default-mode journal line missing ([leadv2-dispatch-code] freepool_floor_mode mode=full source=yaml task=36c27f8d) -- 

=== 23 passed, 8 failed ===

## raw — plugins/leadv2/scripts/tests/test-phase-precondition.sh (falsification proof) (rc=1)
test: F2 plan-for --writes makes deploy mandatory
test: F3 plan-for rejects invalid class
MANDATORY classify
MANDATORY build
NA test docs_only
MANDATORY review
NA deploy no_runtime_surface
MANDATORY close
MANDATORY classify
OPTIONAL plan
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
NA live_verify no_deploy
MANDATORY close
MANDATORY classify
OPTIONAL diverge
MANDATORY plan
MANDATORY gate1
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
MANDATORY live_verify
NA e2e no_deploy
MANDATORY close
MANDATORY classify
MANDATORY diverge
MANDATORY plan
MANDATORY gate1
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
MANDATORY live_verify
MANDATORY e2e
MANDATORY close

[PHASE-PRECONDITION] pass=72 fail=7

verdict: RED
