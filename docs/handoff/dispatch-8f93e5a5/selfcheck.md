# builder selfcheck — dispatch-8f93e5a5
generated_at: 2026-09-03T19:10:43Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01
diff_hash: 0f0115d94d2b1e771ecc8229f9ebbeaaea4105c4007bbe95b1b8b55712db2b6e
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
