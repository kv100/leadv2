# builder selfcheck — dispatch-5825bdd1
generated_at: 2026-09-04T19:41:09Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01
diff_hash: 1a112d06ff6c3545a62e29ff094fc15b46a0c0021b0e3233345b2c5e4983f420
checks: 10   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/leadv2-single-lead-beat.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-duty.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-stale-file.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-duty.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-stale-file.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-broad-status-duty.sh (falsification proof) (rc=1)
[TEST] FAIL: T9a: failure reason missing from the table row
[TEST] FAIL: T9b: previous healthy table still in founder-status.md
[TEST] FAIL: T9b: no СТАТУС НЕ СОБРАН sentence
[TEST] FAIL: T9b: pinned beat timestamp missing
[TEST] FAIL: T9b: line 1 lacks degraded=1: 2026-08-16T00:00:00Z [BROAD_STATUS] dispatched=0
[TEST] FAIL: T9b: failure reason missing from the table row
[TEST] PASS: T9c-healthy: ready-line at= == the artifact's confirmed-write epoch stamp
[TEST] PASS: T9c-degraded: ready-line at= == the artifact's confirmed-write epoch stamp
[TEST] PASS: T9d: unwritable artifact -> zero BROAD_STATUS_READY lines
[TEST] PASS: T9d: exactly one BROAD_STATUS_FAILED stale_file_kept=1
[TEST] PASS: T9d: stale file byte-identical (nothing half-wrote it)
[TEST] PASS: T6: BROAD_STATUS_S=0 -> no beat, no ready-line (rollback whole)
[TEST] FAIL: T7: skip not logged: none
[TEST] PASS: T8a: anchor DIRECTIVE lists the relay in BOTH blocks
[TEST] PASS: T8b: leadv2.md carries the relay contract
[TEST] FAIL: T8b: supervisor-role.md drifted from the relay wording
[TEST] PASS: T8c: CronCreate ban present in leadv2-task-anchor.sh (C4)
[TEST] PASS: T8c: CronCreate ban present in leadv2.md (C4)
[TEST] 
[TEST] === 18 passed, 20 failed ===
FAIL: T3a: pump counter or founder-status.md missing after one loop cycle
FAIL: T3b: no ready-line with dispatched=2 after loop cycle: none
FAIL: T4a: first beat appears (waited 120s)
FAIL: T4b: --ensure did not cleanly adopt the live loop
FAIL: T4c: LOOP_SILENT alarm (waited 60s)
FAIL: T4d: replacement loop started (waited 90s)
FAIL: T4e: fresh beat from the replacement loop (waited 150s)
FAIL: T4f: replacement loop not alive
FAIL: T9a: previous healthy table still in founder-status.md
FAIL: T9a: no СТАТУС НЕ СОБРАН sentence
FAIL: T9a: pinned beat timestamp missing
FAIL: T9a: line 1 lacks degraded=1: 2026-08-16T00:00:00Z [BROAD_STATUS] dispatched=0
FAIL: T9a: failure reason missing from the table row
FAIL: T9b: previous healthy table still in founder-status.md
FAIL: T9b: no СТАТУС НЕ СОБРАН sentence
FAIL: T9b: pinned beat timestamp missing
FAIL: T9b: line 1 lacks degraded=1: 2026-08-16T00:00:00Z [BROAD_STATUS] dispatched=0
FAIL: T9b: failure reason missing from the table row
FAIL: T7: skip not logged: none
FAIL: T8b: supervisor-role.md drifted from the relay wording

verdict: RED
