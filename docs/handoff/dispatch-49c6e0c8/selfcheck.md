# builder selfcheck — dispatch-49c6e0c8
generated_at: 2026-09-03T06:19:06Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SAFETY-PIN-SECOND-DOOR-01
diff_hash: 7d10b77c8978086e7cf2e08ff35601db3713b618bad02ebe2814b11e2c4205d7
checks: 7   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-admission-safety-pin.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SAFETY-PIN-SECOND-DOOR-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-admission-class.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-admission-safety-pin.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
