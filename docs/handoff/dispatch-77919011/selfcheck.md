# builder selfcheck — dispatch-77919011
generated_at: 2026-09-05T20:14:57Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8f14220d1e93
diff_hash: a286c55c9d097fae1116f280fc042cfddae4a63a4a7e82c5bb123570926ce96a
checks: 10   failed: 4   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-idle-lead-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-injector-dedup.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8f14220d1e93/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-idle-lead-guard.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-injector-dedup.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-t14-worker-mcp.sh | ADVISORY (no_falsification_marker) |

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

## raw — plugins/leadv2/scripts/tests/test-injector-dedup.sh (falsification proof) (rc=1)
[TEST] PASS: hook scripts parse
[TEST] PASS: (a) first turn: task-anchor emits a full injection (active-task path confirmed)
[TEST] PASS: (b) second turn unchanged: stub, 4 line(s) <=5, active-task path confirmed
[TEST] PASS: (c) changed state: full re-inject reflects the new goal, active-task path confirmed
[TEST] PASS: (c.delta) turn after a full re-inject collapses back to the stub
[TEST] PASS: (d) unwritable state sidecar: fail-open to full injection
[TEST] PASS: (e) default handoff: true duplicate suppressed, unique content preserved
[TEST] PASS: (e control) LEADV2_ANCHOR_OWNS_CONTEXT=0 legacy path byte-identical to the checked-in 9e9677b golden
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8f14220d1e93/plugins/leadv2/hooks/leadv2-user-prompt-context.sh: line 167: phase: command not found
[TEST] PASS: multisession: 4th session (note+blocked_by) reaches output
/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-injector-dedup.YoOmg7/hooks-mut/leadv2-user-prompt-context.sh: line 167: phase: command not found
[TEST] FAIL: multisession negative control stayed green
[TEST] Results: PASS=9 FAIL=1

## raw — plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh (falsification proof) (rc=1)
=== pass 1/2: post-fix (live tree: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8f14220d1e93/plugins/leadv2/scripts) ===
[TEST][post-fix] PASS C1-tracked-mod
[TEST][post-fix] PASS C2-untracked-new
[TEST][post-fix] PASS C3-clean-anti-rescue
[TEST][post-fix] PASS C4-handoff-only-dirt
[TEST][post-fix] FAIL C5-registered-arm-silent

=== pass 2/2: red-first pre-fix (git archive HEAD) — reds here are EVIDENCE ===
[TEST][pre-fix] PASS C1-tracked-mod
[TEST][pre-fix] PASS C2-untracked-new
[TEST][pre-fix] PASS C3-clean-anti-rescue
[TEST][pre-fix] PASS C4-handoff-only-dirt
[TEST][pre-fix] FAIL C5-registered-arm-silent

Results (post-fix, live tree): 4 passed, 1 failed
FAIL: C5-registered-arm-silent
red-first: 0/4 post-fix-passing cases RED against pre-fix
GREEN-PRE-FIX (not evidence): C1-tracked-mod
GREEN-PRE-FIX (not evidence): C2-untracked-new
GREEN-PRE-FIX (not evidence): C3-clean-anti-rescue
GREEN-PRE-FIX (not evidence): C4-handoff-only-dirt
pre-fix-could-not-run: 0
TRIPWIRE: paths changed under ${LEADV2_REPO}/plugins or ~/.claude during the run (attribution required in report):
/Users/kostiantyn.vlasenko/.claude
/Users/kostiantyn.vlasenko/.claude/burn
/Users/kostiantyn.vlasenko/.claude/leadv2-lane-watch
/Users/kostiantyn.vlasenko/.claude/leadv2-lane-watch/1fe602a3-661d-4b6d-bd02-b321f3f53d16
/Users/kostiantyn.vlasenko/.claude/sessions
/Users/kostiantyn.vlasenko/.claude/leadv2-state/persona-engine

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

[PHASE-PRECONDITION] pass=81 fail=1

verdict: RED
