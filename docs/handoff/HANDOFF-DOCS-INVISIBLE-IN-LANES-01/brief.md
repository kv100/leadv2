# HANDOFF-DOCS-INVISIBLE-IN-LANES-01

A brief written by the lead for a worker is, by default, invisible to that worker. This is the
root cause behind several hours of rework tonight and it will keep costing until it is fixed.

## Measured

`.gitignore:49` is `docs/handoff/*/*`. A lane worktree is a git worktree, so anything untracked in
the main checkout simply does not exist there.

    on disk:  2605 .md files under docs/handoff
    tracked:  1008

So roughly 1600 handoff documents — briefs, addenda, continuation notes, reports — exist only in
whichever checkout wrote them.

**The proof is not theoretical.** `FREEPOOL-MUST-ACTUALLY-GET-WORK-01` round 2 was dispatched with
a mission that said "read `continue-round-2.md` FIRST". The worker could not see that file, nor
`brief.md`, nor `brief-addendum-4.md`. It worked from the positional mission text alone, and the
round ended in nine minutes with one of four causes addressed. Round 3, dispatched after the lead
force-added the briefs, delivered the full acceptance including four negative controls. Same task,
same arm family, the only difference was whether the specification was visible.

The lead has been working around this by hand with `git add -f` per lane. That is a workaround, it
depends on the lead remembering, and tonight it was remembered only after the damage.

## What this task must decide

The ignore rule exists for a reason — handoff directories accumulate large generated junk: diffs,
`*.log`, stream dumps, cost estimates, phase state, review payloads. Tracking all 2605 files is
not the answer and neither is deleting the rule. Work out the right boundary and implement it.
A sketch, not a specification — argue for something better if you have it:

- Track the documents a worker must read: `brief.md`, `brief-addendum-*.md`,
  `continue-round-*.md`, `fix-round-*.md`, `report.md`, and whatever else the census below shows
  is authored-by-a-human rather than generated.
- Keep ignoring the generated bulk, and say what rule distinguishes them.
- Whatever you choose must not require the lead to remember `-f`. If a brief has to be added by
  hand each time, the fix has not landed.

## Definition of done

1. A census first: of the ~1600 untracked files, how many are authored documents versus generated
   artifacts, by extension and by name pattern? Put the counts in the report. The boundary should
   fall out of the census, not out of taste.
2. The `.gitignore` change, with the negation patterns that keep the bulk ignored.
3. A test that fails if an authored brief in a handoff directory is untracked — this is the part
   that stops the regression from coming back. It must be a real test: create a fixture brief,
   show the check goes red, track it, show green. Add the `EXTRA_SUITE_MAP` row so
   `run-all --scope changed` actually selects it, and prove the selection.
4. Retroactive: bring the existing authored briefs under tracking in one commit, and state how
   many files that was. Do not sweep in generated artifacts to make the number look thorough.
5. Confirm the repository size impact in the report — added file count and bytes. If it is large,
   say so rather than hiding it.
6. Commit in this lane before you finish.

Off limits: `main`, deleting the ignore rule wholesale, and any design that still needs the lead to
remember a manual step.
