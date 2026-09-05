# builder selfcheck — dispatch-5540a05e
generated_at: 2026-09-01T16:45:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARDS-MUST-PROVE-THEY-FIRE-01
diff_hash: 578b79554dfdd59405ab93da73cd3678f9b24579b610e08a5f67aa5bc3cb1065
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/fx-always-block.sh | 0 |
| bash -n | plugins/leadv2/hooks/fx-disabled.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARDS-MUST-PROVE-THEY-FIRE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
