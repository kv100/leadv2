# builder selfcheck — dispatch-055185da
generated_at: 2026-08-31T12:10:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-PROVES-ITS-OWN-CONTROL-01
diff_hash: fed3ea2abb121da1c8d8999428b7ecc24280a4aac3bdb412fe25cbac0942c3fa
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/lib/leadv2-control-prover.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-control-prover.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GATE-PROVES-ITS-OWN-CONTROL-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-control-prover.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
