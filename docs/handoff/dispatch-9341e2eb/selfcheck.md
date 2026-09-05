# builder selfcheck — dispatch-9341e2eb
generated_at: 2026-08-23T20:25:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9341e2eb
diff_hash: 3ffc074c32cf0ff22630fee23d86f22947a1eef6836f4a6ae7b1ff00af16f4f9
checks: 7   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 11 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-context-diet-probe.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-subsession-context-diet.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/9341e2eb/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-subsession-context-diet.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
