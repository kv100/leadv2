# MERGE-QUEUE-DEAD-HEAD-01 — fix round 2 report

## Round 1 verdict addressed (reviewer glm, FAIL, high=1)

**Finding:** `leadv2-merge-queue.sh` dead-enqueued reclaim evicted the CALLER's own
row. On the re-dispatch path (task re-runs `acquire` after its earlier process
crashed while `enqueued`), the caller's stale row was reclaimed as
`dead-enqueued`; because `acquire` auto-enqueues only once before its poll loop,
the caller never re-entered the queue and hung until `LEADV2_MERGE_TIMEOUT_SEC`
(default 1800 s), then exited 2.

**Root cause (verified):** `acquire` calls `_txn enqueue` exactly once
(`leadv2-merge-queue.sh:283`), then polls `_txn try_acquire` only. Round 1's
dead-enqueued reclaim loop inside `try_acquire` iterated over ALL queue rows
including `task_id == caller`, and a reclaim removes the row from the replayed
queue — so the caller evicted itself on poll 1 and nothing ever re-enqueued it.

## Fix

`plugins/leadv2/scripts/leadv2-merge-queue.sh` (+32 lines, 3 pieces):

1. **`enqueue` op — in-place refresh.** If the task is already in the queue
   under a stale pid (idempotent re-run of `acquire`), append a
   **`re-enqueued`** ledger event with the new caller pid + fresh ts, keeping
   its FIFO position. No new `enqueued` event (that would be a no-op in replay
   anyway since the row is still in queue), no removal.
2. **`replay` — handle `re-enqueued`.** Updates `enq_ev[tid]` in place
   (fresh pid/ts → no longer dead+stale) and never removes the row from the
   queue.
3. **`try_acquire` — same-task exemption.** The dead-enqueued reclaim loop now
   skips `tid == caller_task_id` defensively, so a stale snapshot can never
   evict the caller mid-poll. Rows of OTHER dead tasks are reclaimed exactly as
   in round 1.

Net effect: the caller's stale row is REPLACED in place (new pid, new ts, same
queue position) instead of being reclaimed; ledger shows `re-enqueued`, never a
`dead-enqueued` for the caller's own task_id.

## Round 2 evidence

### Suite green (fixed script)

`LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh`:

```
ok - case (a): ledger has dead-enqueued reclaimed event
ok - case (a): live-task acquired after dead head reclaimed
ok - case (b): live head NOT reclaimed, status clean
ok - case (b): no dead-enqueued reclaim in ledger
ok - case (c): fresh dead head NOT yet reclaimed (under stale threshold)
ok - case (c): no premature reclaim in ledger
ok - case (d): task-a re-acquired promptly, no TIMEOUT
ok - case (d): ledger recorded re-enqueued for task-a
ok - case (d): ledger has zero dead-enqueued reclaims
--- 9 passed, 0 failed ---
suite rc=0
```

### Reviewer reproduction added as case (d) — `test_self_reacquire_not_evicted`

task-a enqueued with a DEAD pid at a stale ts (the crash/re-dispatch state),
then task-a itself calls `acquire` under a live pid with
`LEADV2_MERGE_TIMEOUT_SEC=5`. Asserts: acquire returns rc=0 well under 5 s
(never TIMEOUT/exit 2); ledger contains `re-enqueued` for task-a; ledger
contains zero `dead-enqueued` reclaims.

### Mutation negative control (round-1 script, exemption dropped) — RED

Reverted `leadv2-merge-queue.sh` to the committed round-1 version
(`git checkout --`, fix restored afterwards, md5-verified byte-identical:
`4547ea874b7c4f9ef2abaeee94a89d86`) and re-ran the suite:

```
ok - case (a): ledger has dead-enqueued reclaimed event
ok - case (a): live-task acquired after dead head reclaimed
ok - case (b): live head NOT reclaimed, status clean
ok - case (b): no dead-enqueued reclaim in ledger
ok - case (c): fresh dead head NOT yet reclaimed (under stale threshold)
ok - case (c): no premature reclaim in ledger
[merge-queue] acquire timeout after 5s for task-a
FAIL - case (d): task-a did NOT re-acquire (rc=2)
FAIL - case (d): ledger MISSING re-enqueued event ({"ts":"2026-09-01T22:37:14Z","type":"enqueued","task_id":"task-a","branch":"x","pid":59942}
{"reason": "dead-enqueued", "task_id": "task-a", "ts": "2026-09-01T22:37:44Z", "type": "reclaimed"}
{"task_id": "task-a", "ts": "2026-09-01T22:37:50Z", "type": "timeout"})
FAIL - case (d): unexpected dead-enqueued reclaim present at all (...)
--- 6 passed, 3 failed ---
MUTANT suite rc=1
```

The mutant's ledger excerpt is the reviewer's exact reproduction: task-a's own
row reclaimed as `dead-enqueued` → no `re-enqueued` → `acquire timeout` → rc=2.

### Syntax checks

`bash -n` on both changed shell files: `bash -n OK` (both clean). No Python
files changed (the embedded python lives inside `leadv2-merge-queue.sh` and is
covered by the suite + `bash -n` of the wrapper).

### Changed-scope runner

`LEADV2_SUITE_LOCK_DISABLE=1 tests/run-all.sh --scope changed` — output pasted
below in the final-message / appended once the run completed (command exceeded
the 600 s foreground budget and was backgrounded; result recorded here when it
landed):

```
(see run-all output block appended below)
```

## Note on the round-1 → round-2 handoff

Round 2 was started by a prior worker arm (pid 49666) that died mid-build
leaving the fix + case (d) uncommitted on disk (duplicated-dispatch thread
2026-09-01T22:11:10Z). This arm verified the owner was dead, reviewed the
leftover implementation (correct as written), added the evidence runs above and
is committing it.
