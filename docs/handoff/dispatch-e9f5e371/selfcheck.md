# builder selfcheck — dispatch-e9f5e371
generated_at: 2026-09-08T17:54:03Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B6-SCOPE-CHANGED
diff_hash: 617d5e25f4167d4d2c475036953db739428ab3dcd45f462869bb655d414b5eef
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/tests/test-scope-changed-is-deterministic.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B6-SCOPE-CHANGED/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-scope-changed-is-deterministic.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
