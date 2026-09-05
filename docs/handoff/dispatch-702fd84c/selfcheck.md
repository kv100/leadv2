# builder selfcheck — dispatch-702fd84c
generated_at: 2026-09-01T23:25:46Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEADV2-HOOK-CACHE-DEPLOY-01
diff_hash: fb677ddbd83f0a24f7440901dace19e3b8596ac6832c3a5d8cb3a5ab9142497b
checks: 47   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | .claude/leadv2-overrides/deploy.sh | 0 |
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
| bash -n | plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-session-runner.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/leadv2-suite-falsifiable.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-task-judge.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-flash-handle.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh | 0 |
| bash -n | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEADV2-HOOK-CACHE-DEPLOY-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-glm-flash-handle.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh | ADVISORY (no_falsification_marker) |
| falsification | /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-suite-falsifiable.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
