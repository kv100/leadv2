# builder selfcheck — dispatch-82bb6960
generated_at: 2026-08-31T20:45:48Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-REPO-SCOPED-03
diff_hash: bb8317ab34d5fe709ce3a6b0e3d7cedeeaa20690e34acddb3df64152167b0ed1
checks: 10   failed: 2   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-repo-scoped.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-REPO-SCOPED-03/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | FAIL (test_failed:rc=124) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | FAIL (test_failed:rc=124) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-row-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-status-repo-scoped.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh (falsification proof) (rc=124)
[TEST] PASS: S1: foreign live lane in the table with repo=foreignrepo

## raw — plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh (falsification proof) (rc=124)
[TEST] PASS: T1a: false 'ДОСКА ПУСТА' headline absent when the lanes section itself failed
[TEST] PASS: T1b: distinct 'не вижу линии' marker present
[TEST] PASS: T1c: the raw collector fail reason is surfaced verbatim, not a generic placeholder
[TEST] PASS: T2: a genuinely empty board (lanes.ok=true, table=[]) still fires the real empty-board headline
[TEST] PASS: T2b: no false 'не вижу линии' marker on a genuinely successful, genuinely empty collector run
[TEST] PASS: T3: table_prefix (full doc) also carries the lanes-unavailable marker

verdict: RED
