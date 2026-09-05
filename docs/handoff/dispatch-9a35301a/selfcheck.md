# builder selfcheck — dispatch-9a35301a
generated_at: 2026-09-01T22:54:55Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MERGE-QUEUE-DEAD-HEAD-01
diff_hash: 63b1eb22350ef0ce18c639a10560a98933dd4ac522e701fdbea813cf751e4795
checks: 33   failed: 1   skipped: 4

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| resolve | plugins/leadv2/scripts/leadv2-suite-falsifiable.sh | SKIP (unresolved_path) |
| resolve | plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | SKIP (unresolved_path) |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-single-lead-beat.sh | 0 |
| bash -n | plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/freepool-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/glm-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/kimi-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-shape.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-merge-queue.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-session-runner.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-task-judge.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MERGE-QUEUE-DEAD-HEAD-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh | ADVISORY (no_falsification_marker) |

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

[PHASE-PRECONDITION] pass=77 fail=2

verdict: RED
