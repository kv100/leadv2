# builder selfcheck — dispatch-9ea4cd03
generated_at: 2026-08-24T17:51:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9ea4cd03
diff_hash: cf31c7b525941a8605cdd2ae227d1bfd2d02873d64df9cc792137625e8dd3a98
checks: 18   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 13 files, write-set honored | 0 |
| bash -n | plugins/leadv2/codex-lead/marketplace/plugins/leadv2/scripts/repowise-launch.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-codex-install.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-repowise-launch.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fanout.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9ea4cd03/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/codex-lead/tests/test-codex-install.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/codex-lead/tests/test-repowise-launch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-burn-governor.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
