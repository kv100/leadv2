# builder selfcheck — dispatch-7ade3187
generated_at: 2026-08-29T20:55:53Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27
diff_hash: f7897cffb91abbee60622f6031f358e0648a201124a9f9ea79e76dec832109f2
checks: 3   failed: 1   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-writeset-admission-block.sh (falsification proof) (rc=1)
[TEST] === lane write-set admission block (LANE-WRITESET-REGISTRY-01) ===
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=97413
[TEST] PASS: live signal: rc=5, conflict names LANE-A, LANE-B not appended
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=97387
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=97387
[registry] writeset conflict: other=RACE-B paths=target/path
[TEST] PASS: race: exactly one intersecting register wins under the registry lock
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=97387
LEADV2_WRITESET_UNKNOWN other=LEGACY
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=97387
[registry] writeset unknown: other=LEGACY
[registry] writeset conflict: other=PEER paths=contested/b
[TEST] PASS: legacy and drift re-check: warn admits, block=6, free=0, contested=5
[lv2_durable_pid] WARNING: no claude process found in PPID chain; using fallback pid=97387
[TEST] PASS: H1: a lane mid-resolution (writes not yet persisted) refuses an intersecting concurrent register, even under warn
[TEST] PASS: H2/H3: _pc_git_diff_names sees an untracked new file and excludes docs/leadv2/
[TEST] PASS: H4: writeset_drift_conflict is never reclassified landed_foreign; unscopable_diff escape still fires
[TEST] FAIL: M1 reclassify wire: Test 1 failed - writeset_drift_conflict incorrectly triggered reclassification. out1=[]
[TEST] === Results: PASS=6 FAIL=1 ===

verdict: RED
