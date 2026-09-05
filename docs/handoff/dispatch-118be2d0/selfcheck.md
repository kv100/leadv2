# builder selfcheck — dispatch-118be2d0
generated_at: 2026-08-27T04:34:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t12prof
diff_hash: fbad9caa1e36985f04ee8c4bfdd8221e9102f63378bdd7d8b06cd3f2a0fc490e
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t12prof/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
