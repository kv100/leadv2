verdict: APPROVE
next_action: review_round_2

# MERGE-QUEUE-DEAD-HEAD-01 round 2 — developer report

Full evidence and reasoning: see
`docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/report.md` in the worktree (git-added
alongside code/test changes, since docs/handoff/<TASK_ID>/ was declared a
LANE_WRITE for this mission and is otherwise gitignored).

## Summary
Round 1 reviewer (glm) found: the dead-enqueued reclaim in
`leadv2-merge-queue.sh` `try_acquire` scanned the caller's own queue row along
with everyone else's, so a task that crashed post-enqueue/pre-acquire and got
re-dispatched had its own row evicted as "dead-enqueued" on its very next
`acquire` call — it never re-entered the queue and hung to `TIMEOUT` (1800s,
exit 2).

## Fix (plugins/leadv2/scripts/leadv2-merge-queue.sh)
1. `enqueue` op: when task_id is already in queue (idempotent re-run) and its
   recorded pid differs from the caller's, append a new `re-enqueued` event
   with the fresh pid/ts instead of silently no-op'ing. `replay()` treats
   `re-enqueued` as an in-place `enq_ev[tid]` refresh — FIFO position
   unchanged.
2. `try_acquire` op: the dead-enqueued reclaim loop now unconditionally skips
   `tid == caller_task_id` — the caller's own row is never reclaimed here,
   defense-in-depth against a stale ledger read between the `enqueue` and
   `try_acquire` transactions.

## Test evidence (plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh)
Added case (d): task-a enqueues under a dead+stale pid, then re-runs
`acquire` under a new live pid. Asserts ACQUIRED promptly (no TIMEOUT),
ledger has `re-enqueued` for task-a, ledger has zero `dead-enqueued` reclaims.

```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh
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
```

Mutation negative control: removed the `enqueue`-side `re-enqueued` refresh
→ case (d)'s "ledger recorded re-enqueued" assertion went RED (8 passed, 1
failed); reverted, `diff` against a pre-mutation backup showed no diff.
(With only the `try_acquire`-side exemption removed, case (d) stays green —
the `enqueue`-side fix is what closes the reviewer's actual race; the
`try_acquire` exemption is kept as defense-in-depth per the mission's
explicit instruction that reclaim must never touch the caller's own row.)

`plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` referenced in the
mission does not exist in this worktree (`find . -iname '*falsif*'` → no
hits) — verified per protocol §6.5 rather than assumed, skipped, and
substituted the manual mutation-control above.

`tests/run-all.sh --scope changed` (LEADV2_SUITE_LOCK_DISABLE=1, 300s
timeout): routed to `run-core-offline.sh` (83 suites/4 shards, includes this
task's suite), exit 0, no FAIL lines. Full output pasted in
`docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/report.md`.

## Self-check
`bash -n` on both changed `.sh` files: BASH_OK. No `.py` files changed this
round.

## Commit
Committed on this lane branch: code fix, test file, and
`docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/report.md` (git-added with `-f`, dir
is gitignored). Did not stage/touch the many unrelated dirty files under
`docs/leadv2/*` and other `docs/handoff/dispatch-*` paths visible in
`git status` — those belong to concurrent lead/lane activity outside this
mission's LANE_WRITES.

DELIVERABLE_COMPLETE
