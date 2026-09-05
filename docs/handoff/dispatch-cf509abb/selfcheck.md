# builder selfcheck — dispatch-cf509abb
generated_at: 2026-09-02T22:36:10Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-UNKNOWN-KIND-01
diff_hash: 2aa20bf467955c35e82038ff819b19283811e33d7dbb22ec282fb2f86682135c
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-UNKNOWN-KIND-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
