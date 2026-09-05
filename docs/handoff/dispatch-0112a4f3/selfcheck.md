# builder selfcheck — dispatch-0112a4f3
generated_at: 2026-08-24T13:15:52Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0112a4f3
diff_hash: f2d5e2f9bc2803ae6e21a6b662bb9048c9b9fb1694b70bbca015097fd16bd8c0
checks: 11   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 18 files, write-set honored | 0 |
| bash -n | plugins/leadv2/codex-lead/install.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/lv2guard.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/marketplace/plugins/leadv2/scripts/repowise-launch.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-codex-install.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/0112a4f3/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/codex-lead/tests/test-codex-install.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
