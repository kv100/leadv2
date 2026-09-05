# builder selfcheck — dispatch-29ac0320
generated_at: 2026-09-04T19:27:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01
diff_hash: d9b70c724486d3b5a5d2504ed48ea37203fe9125e3662c2802c9afa1a2d431e3
checks: 5   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t13-slice2.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ESCALATION-OFFERS-DESTRUCTIVE-DEFAULTS-FOR-FINISHED-LANES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-finished-lane-no-escalation.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t13-slice2.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
