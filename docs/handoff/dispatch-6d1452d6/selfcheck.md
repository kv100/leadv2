# builder selfcheck — dispatch-6d1452d6
generated_at: 2026-09-01T22:12:02Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BEAT-LOOP-ORPHANS-01
diff_hash: 9bb6a1cd308650f2bde4c59c7f8216fff3daaedf6a5a32e625b08112f383a521
checks: 95   failed: 8   skipped: 2

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
| bash -n | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-repo-scoped.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t13-slice2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-watch-lifecycle.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BEAT-LOOP-ORPHANS-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-codex-longrun.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | FAIL (test_failed:rc=4) |
| falsification | plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-guard-census.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-hook-fork-budget.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-model-select-telemetry.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-phase-record.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-papercuts.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-status-repo-scoped.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t13-slice2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-watch-lifecycle.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-effort-routing.sh (falsification proof) (rc=4)
PASS: adversarial-review kind resolves effort=high
PASS: mechanical/docs kind resolves effort=low
PASS: ordinary heavy code build resolves effort=medium
PASS: new yaml-only effort_matrix rule flips the outcome (no script edit)
PASS: unmodified routing.yaml still resolves medium (control for the anti-hardcode case)
PASS: codex arm receives --effort high in its own launch args (distinct from --tier)
PASS: sonnet arm receives --effort in its own launch args, no --tier flag (different shape than codex)

## raw — plugins/leadv2/scripts/tests/test-fork-storm-watcher-liveness.sh (falsification proof) (rc=1)
[TEST] PASS: control: worker-role live pid still reads live-ish (verdict=starting:0)
[TEST] PASS: acc9: watcher-only row is NOT live (verdict=dead:no_handoff_dir)
[TEST] PASS: acc9/probe-contract: watcher_only=1 present for placement probe
[TEST] FAIL: acc8: watcher never wrote its pidfile; fixture could not pin it (stderr: )
[TEST] PASS: acc10: stale-watcher skip carries distinct cause (got: fskh0002:skipped:plan_source_absent_stale_watcher)
[TEST] PASS: acc10 control: genuine skip keeps the bare cause (fskh0003:skipped:plan_source_absent)

[TEST] 5 passed, 1 failed

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
FAIL: (dispatch) arm_floor_applied journal line missing (log: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//fp08-floor.KXybzg/dispatch-out.log) -- 
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
FAIL: (e4b) default-mode journal line missing ([leadv2-dispatch-code] freepool_floor_mode mode=full source=yaml task=de9f5bb9) -- 

=== 23 passed, 8 failed ===

## raw — plugins/leadv2/scripts/tests/test-hook-fork-budget.sh (falsification proof) (rc=1)
  ok: 4: hook dying rc=254 degrades to did-not-run (exit 0)
  ok: 4: degradation is recorded in the journal
  ok: 4: guard's deliberate rc=2 still passes through (deny preserved)
  ok: 4: guard rc=2 did NOT pollute the degrade journal (1 line only)
count Bash: 13 hook commands per call (of 52 wired)
count Edit: 14 hook commands per call (of 52 wired)
  ok: 5: Bash=13 and Edit=14 hook commands per call (<52 wired); all per-call commands tail-exec eligible
  ok: 5: measured: single simple command under sh -c costs 1 process (explicit exec or not)
  ok: 5: control: compound command keeps the extra shell process (suffix would cost +1/hook/call)
Traceback (most recent call last):
  File "<stdin>", line 27, in <module>
AssertionError: event added: SessionEnd
  FAIL: 6: firing set changed (see DIFF lines above)
  ok: 7: fork-budget exits 0
  ok: 7: reports procs_total
  ok: 7: reports procs_mine
  ok: 7: reports orphan_sleep_ppid1
  ok: 7: reports procs_limit_user
  ok: 7: reports verdict
  ok: 7: verdict=healthy
hook-fork-budget: pass=14 fail=1

## raw — plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh (falsification proof) (rc=1)
[TEST] FAIL: W1 replay-safety: rc=0 pulse=
[TEST] FAIL: W2 beat: alive=no pulse=
[TEST] FAIL: W2 dedup noise: watcher exited at, or pulsed, the dedup row (H1)
grep: /tmp/leadv2-lane-pulse-watch-1qZ6JW/repo-cafe0213/docs/leadv2/tasks/dispatch-cafe0213/pulse.md: No such file or directory
[TEST] FAIL: W2 terminal: pulse=
[TEST] FAIL: W5 re-arm dedup: rc=0 event_lines=0
[TEST] FAIL: W3 pidfile: rc=0 before=0 after=0
[TEST] FAIL: W4a baseline: unpatched scratch copy wrote no pulse — the W4 flip below would be vacuous (H2)
[TEST] PASS: W4b negative control RED: tail -n 0 revert misses the pre-existing terminal (as it must)
[TEST] PASS: W6 negative control RED: review_gate-as-terminal revert dies before dispatch_terminal (as it must)
[TEST] FAIL: W7 watch_timeout: rc=0 pulse=
[TEST] FAIL: W8 derived timeout: default= glm= max= pinned= (expected 14700/20300/29100/777)
[TEST] FAIL: W9 worker death: rc=0 pulse=
test-lane-pulse-watch: 2 passed, 10 failed

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

## raw — plugins/leadv2/scripts/tests/test-plugin-papercuts.sh (falsification proof) (rc=1)

test: P1 loop beats through reader errors, stops only on real zeros
[TEST] FAIL: P1a setup: loop pid 60676 died immediately — the loop never ran (vacuous)
[TEST] FAIL: P1b setup: loop pid 61761 died immediately — the loop never ran (vacuous)

test: P2 pidfile cleanup must not delete a NEWER loop claim / suite leaves nothing
[TEST] FAIL: P2a setup: loop A never armed (no live pid in /tmp/leadv2-plugin-papercuts-IxtiaN/p2a.loop.pid)
[TEST] PASS: P2b: suite-scope run exited leaving no beat loop behind

test: P3 rejected codex tier fails LOUDLY at resolution, no fallthrough
[TEST] PASS: P3: tier=spark refused at resolution (rc=1, route_tier_invalid journaled, no route_resolved)
[TEST] PASS: P3b: tier=volume resolves and dispatches normally (rc=0)

test: P4 spawn fallthrough journals a failure naming the arm and reason
[TEST] PASS: P4: codex spawn failure journaled with arm + launcher reason, then route_fallback

test: P5 --resume-lane bare name resolves the lane worktree
[TEST] PASS: P5: bare lane name pins the lane worktree (rc=0)

test: P6 --resume-lane absolute path pins the same worktree
[TEST] PASS: P6: absolute path form pins the lane worktree (rc=0)
[TEST] PASS: P6b: unknown ref refuses with rc=5 and a message showing the accepted shapes

test: P7 task-add.sh dead-write refusal (fixture copy, stubbed curl)
[TEST] PASS: P7: dead Supabase ⇒ rc=1 with an explicit nothing-persisted error
[TEST] PASS: P7b: persisting write still succeeds (rc=0, row returned)

test: P8 watcher argv carries --owner=<repo>:<lane>
[TEST] PASS: P8: spawned watcher argv carries the owner stamp (--owner=p8-repo:worktree-P8-LANE])
[TEST] PASS: P8b: explicit LEADV2_BEAT_OWNER_TAG overrides derivation

test-plugin-papercuts: 11 passed, 3 failed

## raw — plugins/leadv2/scripts/tests/test-watch-lifecycle.sh (falsification proof) (rc=1)
[TEST] FAIL: L1 singleton: live=0 second_exited=yes log=
[TEST] FAIL: L1 beat intact: beats=0 before=0 (dedup changed cadence)
[TEST] FAIL: L2 arm storm: live=0 pidfile_alive=no
[TEST] FAIL: L3 preflight: loop never armed
[TEST] FAIL: L3 owner self-reap: loop survived owner death (alive=no)
[TEST] FAIL: L4 lane-pulse singleton: second_exited=yes count=0 pf= w_first= log=
[TEST] FAIL: L5 preflight: watcher never armed
[TEST] FAIL: L5 lane-pulse owner self-reap: watcher survived owner death (alive=no)
[TEST] PASS: L6 no-growth: 3 spawn/kill cycles, live count back at baseline (0)
[TEST] PASS: L7 negative control RED: blind-write revert arms TWO loops under the L1 scenario (as it must)
test-watch-lifecycle: 2 passed, 8 failed

verdict: RED
