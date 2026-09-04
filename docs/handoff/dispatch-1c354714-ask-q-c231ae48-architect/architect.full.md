# architect — ask-timeout decision (dispatch-1c354714, q-c231ae48)

## Question
Bounded changed-scope runner left verified lane-local PIDs 84549 and 84558 holding
`/tmp/leadv2-core-offline.lock`; the sandbox denies a precise TERM. May the control-plane
owner terminate them so the gate can be rerun?

## Decision
DECISION_OPTION: b
RATIONALE: the PIDs are verified lane-local suite leftovers, not third-party work, and a held /tmp lock is a machine-global blocker that will fail every future gate run until it is released.

## Reasoning

1. **Ownership is established, so the risky part of a kill is already retired.** The
   objection to terminating a PID from a sandboxed lane is that the PID might belong to
   another lane or to the founder's own shell. The question states both PIDs are *verified*
   lane-local suite processes. Under that premise option (b) is ordinary cleanup of the
   lane's own children, not an action against a neighbour.

2. **`/tmp/leadv2-core-offline.lock` is machine-global, not lane-scoped.** A worktree gives
   filesystem isolation for the repo; it gives none for `/tmp`. Leaving the lock held does
   not merely block this lane's rerun — it blocks the offline-core suite for every
   concurrently active dispatch (`dispatch-7c9da953`, `dispatch-6409fada` are live right
   now). Option (a) converts one lane's stall into a shared-resource stall of unbounded
   duration, because nothing else in the system is scheduled to reap that lock.

3. **Option (a) contradicts D3.** `D3: "The red-proof gate reports, it does not trap the
   lane."` Preserving the processes and reporting the gate blocked is exactly a trapped
   lane: no verdict is produced, the gate neither passes nor emits a RED artifact, and the
   close path has nothing to name under D2 (`a named fix owes a RED artifact; an unbacked
   claim closes as unproven, by name`). D2's remedy for missing proof is *close as unproven
   by name*, not *hold the lane open indefinitely* — but that remedy only applies once the
   gate has actually run and reported. Here the gate cannot run at all.

4. **The action is cheap and reversible in the only sense that matters.** These are test
   processes with no durable side effects outside the lock file and their own scratch
   output; killing them loses at most one already-stalled suite run, which is being rerun
   by construction. There is no committed state, no remote call, and no founder-visible
   artifact at risk.

## Constraint on the executor (not a new decision — a boundary on option b)

Because the decision authorises a kill, it must not widen into a pattern-match sweep:

- Terminate **exactly PIDs 84549 and 84558**, by number. No `pkill -f`, no name/pattern
  matching, no "and anything else holding the lock" — a pattern kill is precisely how a
  neighbouring lane's suite gets taken down, and neighbours are live.
- Re-confirm each PID's identity immediately before signalling (a PID freed by natural exit
  can be recycled to an unrelated process between the earlier verification and the kill).
  If either PID no longer matches the verified lane-local suite command line, skip it and
  attempt the lock release alone.
- Prefer TERM; escalate to KILL only if the process survives a short grace period.
- After termination, verify `/tmp/leadv2-core-offline.lock` is actually released (a stale
  lock *file* may persist even after the holder dies, depending on the locking discipline);
  if it persists with no live holder, remove the stale file, then rerun the gate.
- Record the terminated PIDs and the lock state before/after in the lane journal, so the
  rerun's result is attributable and the kill is auditable.

## Out of scope
- Redesigning the lock (lane-scoped path, PID-stamped lock file, or an automatic stale-lock
  reaper). That is the real fix for the recurrence, but it is a separate task and touches
  paths outside this lane's write set — file it in the backlog, do not do it here.
- The `off_limits` items: seven-worker-death commit problem; lane liveness / registration
  defects. Neither is touched by this decision.
- The unrelated open question in `founder-status.md` about adding
  `leadv2-dispatch-product-close.sh` to `LANE_WRITES`.

DELIVERABLE_COMPLETE
