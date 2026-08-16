# MISSION — FORK-RUNS-A-SESSION-01: a fork should be able to run a whole `/leadv2` session, Phase 0→8

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2`. Track 5.4, **founder-ordered**, never
advanced.

Today a fork is used for fragments — a review, a judgement, a synthesis — and the lead stays the only
thing that can carry a task from intake to close. That makes the founder's attention the scarce
resource: every session needs a lead in the loop, and when the lead's context fills, the work stops.
The order is that a fork should be able to run the whole thing: Phase 0 intake through Phase 8 close,
inheriting the session's context rather than starting cold.

## Establish the honest boundary first

Before building, determine and state which phases a fork **can** own today and which it cannot,
with the reason for each. Likely obstacles, to confirm rather than assume:

- Phase 3 Gate 1 wants founder input — how does a fork ask, and who sees the question?
- Phase 6 deploy calls `ExitWorktree`, which the lead is required to call directly.
- Phase 8 close writes shared state (`active.yaml`, board, journals) that a concurrent lead also writes.

A design that pretends these do not exist will fail at exactly the moment it is trusted.

## Then build the smallest real thing

Not a framework: the narrowest path by which a fork carries one task end to end, with the phases it
cannot own explicitly delegated back and **named in the report**. If the honest answer is that a fork
can own Phases 0–5 and must hand back at deploy, that is a real and useful result — say so plainly
rather than faking the last three phases.

## How to prove it

Run one task through it. Not a description of how it would work — an actual pass, with the artifacts
it produced. A design document alone does not close this.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Do not weaken any gate to make the fork's path shorter. A fork that skips review is worse than no
  fork.

## Deliverable
The implementation, the one real pass with its artifacts, and
`docs/handoff/FORK-RUNS-A-SESSION-01/report.md` naming which phases a fork owns, which it hands back,
and why. End with DELIVERABLE_COMPLETE.
