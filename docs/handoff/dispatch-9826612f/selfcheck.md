# builder selfcheck — dispatch-9826612f
generated_at: 2026-08-24T10:36:13Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9826612f
diff_hash: 99660b2334debc88bf5721515287cad4814e16d5269af9f2cb219a65813e1144
checks: 8   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 16 files, write-set honored | 0 |
| bash -n | plugins/leadv2/codex-lead/install.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/leadv2-codex-status.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/lv2guard.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-codex-install.sh | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9826612f/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/codex-lead/tests/test-codex-install.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
