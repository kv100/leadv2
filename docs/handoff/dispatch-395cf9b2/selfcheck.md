# builder selfcheck — dispatch-395cf9b2
generated_at: 2026-09-03T19:53:19Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CI-SUITES-ARE-MACOS-ONLY-01
diff_hash: 66e6e73b71b5fc8583a2fc52b6936351e931282cb9eeba4059c9fdd37db246ff
checks: 9   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-proof-lib.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-skill-proof.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.5s.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-mktemp-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CI-SUITES-ARE-MACOS-ONLY-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-mktemp-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
