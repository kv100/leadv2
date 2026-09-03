# CONTROL-PLANE-HAS-NO-OWNER-01

Nothing owns lane state. Five separate mechanisms each hold a piece of the answer to "is this lane
alive, and what happened to its work", they disagree with each other, and no one of them is
authoritative. Every expensive failure of the last two days is a symptom of that single absence.

Estimated 3–5 days. Founder granted the lead autonomy over how to do it (2026-09-03).

**Barrier cleared.** The five-day sweep is delivered — `docs/handoff/FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01/VERDICT.md`
(commit `c0820151`); every not-clean row carries a task id or a written reason. `SD-FIVE-DAY-AUDIT-BEFORE-STATE-OWNER-01`
is closed by evidence. Read that verdict before starting: it is the ground truth about what is
actually live in this plugin, and its headline finding — *32 of 35 features are live only because
they patched already-wired files; every dead one was a new standalone script nobody calls* — is a
direct warning about how this task can fail.

## The symptoms, all measured 2026-09-02..03

These are not five bugs. They are five views of one missing owner.

| # | symptom | measured |
|---|---|---|
| 1 | **The registry stamps the lead's PID, not the worker's.** A lane looks alive because the lead is alive. | `LANE-REGISTRY-STAMPS-THE-LEAD-PID-01` |
| 2 | **Liveness is read from log freshness, not from the registry.** Unregistering a row from `active.yaml` changes nothing. | verified by hand: the row was removed, `lane_placement_refused reason=lane_is_live` continued |
| 3 | **A worker outlives its own terminal state.** `terminal=no_work cause=empty_diff` written while the worker went on to produce 52 lines. Three more reproductions the same day. | `WORKER-OUTLIVES-ITS-TERMINAL-STATE-01`, lanes `8b995f4a` / `d7c0721d` / the WORKER-OUTLIVES lane itself |
| 4 | **A live process holding the stream deadlocks re-dispatch.** `silent_max` is 900s and the file never goes quiet, so the lane is permanently `lane_is_live`. Only killing the PID by hand freed it. | `LANE-REGISTRY-SELF-DEADLOCK-01`, named in code |
| 5 | **The status surface shows corpses and hides the living.** The 09:07Z and 09:37Z pulses both said "линий нет" with two lanes provably running; `leadv2-lane-liveness.sh --json` returned exactly one lane, a finalized corpse. | `STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01` |

Cost so far: **four separate rescues of committed-less work by the lead's own hands** — 25 files
(freepool), 52 lines (`b794a736`), 23 files (`adf89c9b`), and one lane resumed after its worker died
holding a finished commit it never proved. The lead should never be the mechanism that saves a
lane's work. Today it is the only one.

## What "an owner" has to mean here

Do not start by writing a new component. Audit 1's finding is that a new standalone script nobody
calls is exactly how work in this plugin dies. The owner has to be **the thing already on the
dispatch path**, extended — or, if a new component is genuinely right, its wiring is deliverable #1
and is proven by a live run before anything else is built.

The owner must be able to answer these four questions, and every other mechanism must ask *it*
rather than deriving its own answer:

1. **Is this lane alive?** From the worker's own identity, not the lead's PID and not a file mtime.
   A lane whose worker is gone is not alive, however fresh its log; a lane whose worker is running is
   alive, however quiet.
2. **Has this lane reached a terminal state, and is that state true?** A terminal state may not be
   recorded while the producer can still produce. Symptom 3 is the whole task in one line.
3. **Where is this lane's work?** Committed, uncommitted, or lost. An answer of "uncommitted" must
   trigger the commit, not a chat message to the founder.
4. **May this lane be re-dispatched?** Symptom 4 is a deadlock: the refusal must come from the owner's
   verdict, and there must exist a bounded path from "worker gone" to "dispatchable" that no human
   walks by hand.

## Required deliverables

1. **A census first, before any design.** Enumerate every place that today writes or reads lane
   state: `active.yaml`, the registry writer, `leadv2-lane-liveness.sh`, the close gate in
   `leadv2-dispatch-product-close.sh`, `claude-subsession.sh`'s post-exit epilogue, the pulse/status
   surface, `dispatch_terminal` journal rows, the phase records. For each: what it writes, what it
   reads, and which of the four questions it thinks it is answering. Deliver this table before
   proposing anything. **It is very likely there are more than the five above** — the ones above are
   the ones that bit us, not the ones that exist.
2. **A written decision on the owner's shape**, argued against the census, naming what gets deleted.
   This task must *reduce* the number of mechanisms holding lane state. If the count goes up, the
   design is wrong.
3. **Migrate every reader**, one at a time, each with its own proof. A reader still deriving its own
   answer is a reader that will disagree again.
4. **The four symptoms above, each with a named negative control.** For each: reproduce it, show the
   suite red, apply the fix, show green. Symptom 3 in particular needs a test that a worker with a
   recorded terminal state is gone within a bounded time, and symptom 4 a test that a lane goes from
   "worker gone" to "dispatchable" with no human step.
5. **Work must survive every path.** The four rescues above are the acceptance bar: reproduce each
   shape and show the work is committed without the lead touching it.
6. Green on macOS and in a Linux container, exit codes pasted. Every new suite registered in
   `tests/run-all.sh` and proven to be selected by `--scope changed`.
7. **Kill rate may not go down.** Add each symptom's mutation to the catalog; never delete an entry
   to make the number look better.
8. Commit in the lane after every deliverable, not once at the end. This task is long enough that a
   single dead worker must not cost more than one deliverable.

## Sequencing

The four defects already filed — `LANE-REGISTRY-STAMPS-THE-LEAD-PID-01`,
`WORKER-OUTLIVES-ITS-TERMINAL-STATE-01`, `LANE-REGISTRY-SELF-DEADLOCK-01`,
`STATUS-SURFACE-SHOWS-CORPSES-AND-BACKLOG-01` — are this task's symptoms, not separate work. Any of
them already landed when this starts is a symptom that must still appear in the census and in the
negative controls; a point fix does not remove the need for the owner. Note that
`WORKER-OUTLIVES-ITS-TERMINAL-STATE-01` has committed but **ungated** work (`adf89c9b`) pending
`SD-WORKER-OUTLIVES-VERIFY-01` — treat it as unproven until that row closes.

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, raising `silent_max` to
paper over symptom 4, pruning worktrees while any lane runs (that has already killed two live lanes),
and committing inside any MythicalGames repo.
