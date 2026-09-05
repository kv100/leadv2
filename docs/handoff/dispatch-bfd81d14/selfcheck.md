# builder selfcheck — dispatch-bfd81d14
generated_at: 2026-09-04T23:34:47Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-5FA969AC-01
diff_hash: 3178ff2833b180f16ae2389e7ee198ab31c35650e2cde166da1131fa441e55ab
checks: 8   failed: 2   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 6 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-no-work-terminal.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-5FA969AC-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-no-work-terminal.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh (falsification proof) (rc=1)
PASS: bash syntax: arbiter + dispatch
PASS: (b) standard build: freepool not selected (SELECTION outcome asserted, not just the journal line)
PASS: (b) standard build: floor journaled as floor_applied=1 floor_reason=standard/code
PASS: (b) standard build: freepool demoted to LAST chain position (codex,freepool)
FAIL: (b) standard build: codex/sonnet do not both rank ahead (codex,freepool) -- 
PASS: (b) state file: JSON with arm + task=deadbeef stamp + floor bookkeeping
PASS: (b2) heavy build: freepool not selected
PASS: (b2) heavy build: no floor token when freepool is not in the candidate set
PASS: (b2) strategic build: freepool not selected
PASS: (b2) strategic build: no floor token when freepool is not in the candidate set
PASS: (c) bulk build: freepool still selectable
PASS: (c) bulk build: no floor token for bulk
PASS: (c2) trivial build: freepool still selectable (floor keys on raw class)
PASS: (c2) light build: freepool still selectable (floor keys on raw class)
PASS: (c3) standard docs: freepool still selectable (floor is build-only)
PASS: (dispatch) arm_floor_applied journal line emitted from the arbiter's own output
PASS: (dispatch) route_resolved did not pick freepool (selection outcome)
PASS: (a) bulk build resolved to freepool
PASS: (a) waiter did not declare no_work early (worker finishes at t+8s, window is 3s)
PASS: (a) freepool run finalized complete after the window
PASS: (a) run left a REAL diff on disk (diff.patch with hunks)
PASS: (negative-control) floor mutation applied to a throwaway arbiter copy
PASS: (negative-control) with the floor removed, (b) runs RED: freepool WINS the standard build and the floor token vanishes
PASS: (e1) env full: freepool WINS the standard build (inverse of (b))
PASS: (e1) env full: no floor token in full mode
PASS: (e1) env full: floor_mode=full floor_mode_source=env tokens present
PASS: (e2) yaml full: freepool WINS the standard build
PASS: (e2) yaml full: floor_mode=full floor_mode_source=yaml tokens present
PASS: (e3) garbage env falls through to the yaml key (bulk_only, source=yaml)
PASS: (e3) no env + no yaml key: default bulk_only, source=default
PASS: (e4) freepool_floor_mode mode=full source=env journaled by the dispatcher
PASS: (e4) floor mode full: route_resolved PICKS freepool for a standard build
PASS: (e4b) no override: mode=bulk_only source=yaml journaled (canonical arm.yaml key)

=== 32 passed, 1 failed ===

## raw — plugins/leadv2/scripts/tests/test-no-work-terminal.sh (falsification proof) (rc=1)
[TEST] PASS: finished empty worker exits 5
[TEST] PASS: finished empty worker may emit empty_diff/no_work
[TEST] PASS: finished empty worker journals empty_diff
[TEST] PASS: finished empty worker writes no_work terminal row
[TEST] PASS: live worker timeout exits 5
[TEST] PASS: timeout gate says worker_timeout
[TEST] PASS: timeout journals dead/timeout
[TEST] PASS: timeout writes dead/timeout terminal row
[TEST] PASS: timeout never emits no_work
[TEST] PASS: codex finished-empty path remains no_work
[TEST] PASS: codex wrapped jobs verdict is polled through done
[TEST] PASS: codex close honors registry-root seam until handle clears
[TEST] PASS: Sonnet natural completion reaches non-empty close path
[TEST] PASS: Sonnet close waits for numeric PID exit
[TEST] PASS: Sonnet exit-time diff is classified after natural completion
[TEST] PASS: revived reaches ordinary empty-diff terminal
[TEST] PASS: revived ignores stale original registry handle
[TEST] PASS: revived never writes dead/timeout
[TEST] PASS: revive_blocked_by_gate reaches ordinary empty-diff terminal
[TEST] PASS: revive_blocked_by_gate ignores stale original registry handle
[TEST] PASS: revive_blocked_by_gate never writes dead/timeout
[TEST] PASS: live close watcher extends lease without changing claim ownership
[TEST] PASS: committed worker reaches non-empty close path
[TEST] PASS: committed-ahead diff is non-empty despite clean worker path
[TEST] PASS: committed worker terminal reflects committed diff
[TEST] PASS: slow Codex probe reaches bounded timeout path
[TEST] PASS: Codex probe latency stays inside wait budget
[TEST] PASS: Codex probe failures stay quiet
[TEST] FAIL: freepool diff-writing worker exits through non-empty path (got '5' want '0')
[TEST] FAIL: freepool review.diff is empty
[TEST] FAIL: freepool worker misclassified no_work (the live FP-08 defect)
[TEST] FAIL: freepool terminal row is not landed
[TEST] PASS: freepool liveness resolves through its own author case
[TEST] PASS: freepool rides the shared waiting_worker beat
[TEST] PASS: freepool timeout reaches the bounded worker_timeout path
[TEST] PASS: freepool honors LEADV2_PC_FREEPOOL_MAX_WAIT_S (2s), not 60s (4s)
[TEST] PASS: freepool timeout gate says worker_timeout
[TEST] PASS: freepool timeout never emits no_work

=== 54 passed, 4 failed ===

verdict: RED
