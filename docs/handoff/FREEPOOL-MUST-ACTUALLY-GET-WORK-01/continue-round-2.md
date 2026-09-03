# FREEPOOL-MUST-ACTUALLY-GET-WORK-01 — round 2 (continue an unfinished round 1)

Round 1's worker was reaped `cause=worker_died_stale` at 01:39:41Z without recording a terminal
state, holding all its work uncommitted. The lead committed it verbatim as `8dc52ff4` — 25 files,
nothing lost, nothing altered, **nothing reviewed or verified**.

**Read `git show 8dc52ff4 --stat` and its diff FIRST. Do not start over.** Round 1 already
touched `freepool-coder.sh`, `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh`,
`lib/leadv2-worker-epilogue.sh`, `tests/run-all.sh`, and added
`plugins/leadv2/scripts/tests/test-freepool-gets-work.sh` plus edits to two existing freepool
suites. Your job is to finish and PROVE it, not to redo it.

## The specification is `brief.md` + `brief-addendum-4.md` in this directory

They carry the four measured causes and the founder's correction on classifier authority
(the classifier is authoritative; the defects are that its override is silent and that
`--task-class` is accepted-then-ignored). Nothing there is superseded by this file.

## What round 2 must deliver

1. **Assess what round 1 built.** For each of the four causes say whether `8dc52ff4` addresses it,
   partially addresses it, or does not touch it — with file:line. It was never reviewed, so if
   something in it is wrong, say so and fix it.
2. **The acceptance from `brief.md` is unchanged:** a dispatch of a lane whose write-set is only
   `tests/` + `docs/handoff/`, with NO manual flag, shows `route_resolved ... arm=freepool` in
   the journal. Paste the line.
3. **A negative control per cause you claim fixed.** Name the mutation, show red, revert, show
   green. A claim without its negative control does not count as done.
4. **Cause (2) is now proven by this task twice over, so treat it as first-class.** Round 1 of
   `CI-SUITES-ARE-MACOS-ONLY-01` died at the turn cap holding 10 uncommitted files; round 1 of
   THIS lane died stale holding 25. Write the checkpoint so a worker that dies at any point has
   already committed what it had. A bare limit bump is still not an acceptable answer.
5. **Commit before you finish.** Two rounds of this exact task have now been lost to not doing it.

Off limits: `main`, the capability floor (do not delete or weaken it), and anything that reduces
safety on real protected paths.
