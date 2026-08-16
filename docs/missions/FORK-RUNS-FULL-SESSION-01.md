# MISSION — FORK-RUNS-FULL-SESSION-01 (a fork should be able to run a whole /leadv2 session, Phase 0→8)

Work in `~/Projects/leadv2`. Founder-ordered, and he was emphatic about it: "это надо сделать
точно."

## Why this exists

Today the lead is the only thing that can carry a task from intake to close. Everything else is a
worker that does one step and returns. That has two consequences the founder has now watched all
day:

- The lead is a bottleneck. It spent a full day shepherding lanes through review rounds one at a
  time, and its own context is the scarce resource — every lane it supervises costs context that
  is then unavailable for the next one.
- When the lead's context fills, the session compacts, and continuity depends on files the lead
  remembered to write. A task in flight at that moment is at its most fragile.

A fork inherits the parent's full context and runs independently. If a fork could run a complete
`/leadv2` session — Phase 0 intake through Phase 8 close — then a whole task, not a step, could be
delegated.

## What to determine and build

**First, establish what actually blocks this today.** Do not assume it is impossible; do not
assume it is trivial. Walk `SKILL.md`'s phase list and the scripts each phase calls, and name
concretely which ones cannot run in a fork and why — locking (`Phase 0` takes a lockfile and
registers in `active.yaml`), worktree entry, the interactive gate at Phase 3, the deploy step at
Phase 6, the close writes at Phase 8. Some of these are genuine blockers and some are only
conventions.

**Then build the smallest thing that works end to end.** A fork that can carry one real task from
intake to close is worth more than a design for one that could carry any task. Pick the narrowest
task shape that exercises all nine phases and make that work. Say explicitly what shapes are NOT
supported yet.

**Get these three right or the feature is a liability:**

- **Two sessions must not collide.** The lockfile and `active.yaml` registration exist because
  concurrent `/leadv2` runs corrupt each other. A fork running a full session is a second
  `/leadv2` by any other name. Say how you keep them apart.
- **Gate 1 in a fork.** The one human gate cannot silently auto-accept just because the parent is
  elsewhere. `LEADV2_ASYNC_QUESTIONS` and `leadv2-ask.sh` already exist for exactly this — use
  that path, or say why it does not fit.
- **A fork that dies must be visible.** Today a background worker that dies silently looks
  identical to one still working; that has cost real work repeatedly. A fork owning a whole task
  makes that failure much more expensive, so it needs a liveness signal the parent can check.

## Hard constraints
- No phase may be skipped to make this work. A fork that runs Phase 0→8 runs all of it, including
  review and live verification. A "fork session" that quietly omits the gates is worse than no
  fork at all.
- Plugin repo only.

## Evidence required
A transcript or log of one real task carried by a fork from intake to a written
`phase8-passed.flag`, with the review gate's verdict visible in it. Report to
`docs/missions/FORK-RUNS-FULL-SESSION-01.report.md`. End with DELIVERABLE_COMPLETE.
