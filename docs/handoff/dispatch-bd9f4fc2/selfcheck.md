# builder selfcheck — dispatch-bd9f4fc2
generated_at: 2026-09-01T22:27:19Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKERS-MUST-COMMIT-01
diff_hash: 214338bb28e01ca6caa60b8d049030d3febba7e6e105786d96279ef0d96aafeb
checks: 20   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/freepool-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/kimi-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKERS-MUST-COMMIT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-v2.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-action-binding.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-classified-block.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
