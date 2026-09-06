# D1-SINGLE-WRITER-FOR-LANE-STATE

Repo: ~/Projects/leadv2 (SHARED TREE — never `git add -A`, never `reset --hard`, never `clean`,
never `stash`, never push to origin. Name every path in `git add`, then confirm with
`git diff --cached --name-only`.)

**COMMIT AFTER EVERY STEP.** Five workers died on this machine on 2026-09-06, every one of them
after writing real code and before committing it. Your commits are the only thing that survives you.

This is a design-then-build task and the design half is the hard half. Do not start editing until
the census below is written down.

## The problem

Lane state has **many writers and no owner**. Four separate files define `leadv2_active_register()`
— `leadv2-helpers.sh`, `leadv2-backlog-pump.sh`, `leadv2-active-registry.sh`, `leadv2-fanout.sh` —
and the registry `~/.claude/leadv2-state/persona-engine/active.yaml` is also written by the close
path, the recovery path and the pulse. The consequences are live and were measured on 2026-09-06:

- Rows sit at `phase=recovered_unowned` with `session_id: recovered` — nobody owns them and nothing
  ever closes them. Seven such rows were live in one session.
- A row released by one writer makes another writer's release return `rc=4 "task not registered"`,
  which reads as a silent no-op bug and is not one.
- A merged, finished lane still showed `phase=build` in the registry hours after its merge.
- The pulse reports lanes as ghosts (`ПРИЗРАК?(liveness-probe: unknown)`) from these same rows.

## What to deliver

1. **A written census first**, committed before any code: every writer of `active.yaml` and of the
   per-task journal address, what each writes, and under which lifecycle event. Enumerate by
   grepping the tree — do not reason from this brief's list, which is a starting point and may be
   incomplete. If you find a writer this brief does not name, that is the most valuable line in
   your report.
2. **One owner for each transition.** Decide who writes `register`, who writes each phase advance,
   who writes `finished`, and who is allowed to write `recovered`. The other call sites route
   through the owner rather than writing the file. Justify the choice; there is more than one
   defensible answer and the reasoning is the deliverable.
3. **Make `recovered_unowned` reachable only by a real recovery**, with an explicit expiry or a
   reaper, so a row cannot sit unowned forever.
4. Keep every existing public entry point working. A caller that today calls
   `leadv2_active_register` must keep working, even if the body now delegates.

Note that sourcing `leadv2-active-registry.sh` enables `set -e` in the caller, which silently kills
the calling shell on any non-zero return — this has already produced one wrong diagnosis. Whatever
you design must not make that worse, and say in the report whether you fixed it or left it.

## Proof required

1. A suite that drives the full lifecycle through the owner — register → phase advances → finished —
   and asserts one row, one writer, correct terminal state.
2. **A negative control**: a row that is genuinely unowned STILL becomes `recovered`, and a second
   writer attempting a transition it does not own is refused rather than silently winning. A fix
   that merely removes the duplicate functions passes the first test and destroys recovery.
3. Mutation control, named in the suite header, applied INSIDE the changed function's body — a
   line-number insert at top level makes everything red for the wrong reason and reads as a pass.
   Show both colours with the run output.
4. CI selection, stateful: `rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"`,
   then `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`; capture to a FILE and
   grep it — never pipe through `head`, which truncates evidence and reads as absence.
5. Run every suite that guards each file you touch (`# run-all-triggers:` headers). Baseline any red
   against clean main in a detached worktree before calling it a regression — 16 of 85 suites are
   red on main right now, so an unbaselined red is almost certainly not yours.
6. `tests/known-red-suites.txt` may only SHRINK.

`rc=0` means nothing — read the summary line; `rc=$?` after a pipe reads the LAST stage's status.
Derive every zero a second way; seventeen confident-zero errors were logged here in one night.

## Report

`docs/handoff/D1-SINGLE-WRITER-FOR-LANE-STATE/report.md`, under 100 lines: the writer census, the
ownership decision and its alternatives, what happens to the seven currently-unowned rows, and all
six proofs with their output.
