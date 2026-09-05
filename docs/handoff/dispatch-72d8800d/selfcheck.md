# builder selfcheck — dispatch-72d8800d
generated_at: 2026-08-31T11:43:42Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DETACH-01
diff_hash: d3abbfab143415c8345da23659eee21f6d47d4bc95cc8ede9670e3807e11fd7d
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DETACH-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-broker-staleness.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
