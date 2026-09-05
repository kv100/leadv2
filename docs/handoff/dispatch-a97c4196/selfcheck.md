# builder selfcheck — dispatch-a97c4196
generated_at: 2026-09-03T19:08:40Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D5-STATUS-SURFACES-ONE-SOURCE-01
diff_hash: eebc4433d3244128afcfe1f39564ec5cab6a0933a1fc8621e26469ae7537dc7e
checks: 3   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D5-STATUS-SURFACES-ONE-SOURCE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh (falsification proof) (rc=1)
[TEST] PASS: S1: foreign live lane in the table with repo=foreignrepo
[TEST] PASS: S4: own-repo mirror slug skipped by the -ef filter, foreign repo still read
[TEST] PASS: S2: single-repo output byte-identical with --all-repos on (consumer safety)
env: snap: No such file or directory
[TEST] FAIL: S3: 
[TEST] PASS: R1: foreign lane rendered with slug prefix, no false empty board
[TEST] PASS: R1b: foreign row carries its stream age
[TEST] PASS: R2: foreign read failure -> named degraded line, table not zeroed
[TEST] PASS: R3: own-repo row unprefixed (single-repo founder-status shape unchanged)

[broad-status-foreign-lanes] PASS=7 FAIL=1

verdict: RED
