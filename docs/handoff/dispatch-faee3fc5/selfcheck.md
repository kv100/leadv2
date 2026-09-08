# builder selfcheck — dispatch-faee3fc5
generated_at: 2026-09-05T21:16:41Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MAIN-CORE-SUITE-RED-01
diff_hash: be45bdd32b968591b11491238f4935ac82ad3aeb7abfb63db2b0798dbdd8d19e
checks: 7   failed: 2   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-idle-lead-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-injector-dedup.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MAIN-CORE-SUITE-RED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-idle-lead-guard.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-injector-dedup.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-idle-lead-guard.sh (falsification proof) (rc=1)
[TEST] PASS: case 1: queued+0live blocks with reason naming task id
[TEST] PASS: case 2: queued+1live allows stop (empty stdout)
[TEST] PASS: case 3: no queued work allows stop
[TEST] PASS: case 4: pending question allows stop
[TEST] PASS: case 5: 8 blocks then 9th allows with cap warning
[TEST] PASS: case 6: kill switch allows stop silently
[TEST] PASS: case 7a: malformed stdin allows stop
[TEST] PASS: case 7b: deleted tasks.yaml allows stop
[TEST] PASS: case 7c: absent liveness probe allows stop
[TEST] PASS: case 7d: unavailable liveness allows stop
[TEST] PASS: case 8: no docs/leadv2/ allows stop
[TEST] PASS: case 9: counter resets on allow, re-blocks from 1
[TEST] FAIL: case 10: registration assertion failed
[TEST] PASS: case 11: unwritable state dir allows stop on all 10 calls (call2=empty call5=empty call10=empty )
[TEST] PASS: case 12: unresolvable questions dir allows stop, stderr names it
[TEST] PASS: case 13: pending question allows stop, stderr names id
[TEST] PASS: case 14: writable state dir still reaches cap at 8/8
[TEST] PASS: case 15: unsatisfied goal does not suppress a legitimate block
[TEST] PASS: case 16: satisfied file_exists goal allows stop

[TEST] idle-lead-guard: PASS=18 FAIL=1
[TEST] FAIL: case 10: registration assertion failed

## raw — plugins/leadv2/scripts/tests/test-phase-precondition.sh (falsification proof) (rc=1)
test: F2 plan-for --writes makes deploy mandatory
test: F3 plan-for rejects invalid class
MANDATORY classify
MANDATORY build
NA test docs_only
MANDATORY review
NA deploy no_runtime_surface
MANDATORY close
MANDATORY classify
OPTIONAL plan
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
NA live_verify no_deploy
MANDATORY close
MANDATORY classify
OPTIONAL diverge
MANDATORY plan
MANDATORY gate1
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
MANDATORY live_verify
NA e2e no_deploy
MANDATORY close
MANDATORY classify
MANDATORY diverge
MANDATORY plan
MANDATORY gate1
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
MANDATORY live_verify
MANDATORY e2e
MANDATORY close

[PHASE-PRECONDITION] pass=80 fail=2

verdict: RED
