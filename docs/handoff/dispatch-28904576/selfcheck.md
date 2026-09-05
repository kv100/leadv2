# builder selfcheck — dispatch-28904576
generated_at: 2026-08-24T14:01:28Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/28904576
diff_hash: 4c1be681b973a2f5ec5a7fb03acaff9b25f9a6ff18e943d0df8359f231bf19ff
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | 0 |
| bash -n | plugins/leadv2/tests/test-deny-floor.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/28904576/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/codex-lead/tests/test-lv2guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-deny-floor.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
