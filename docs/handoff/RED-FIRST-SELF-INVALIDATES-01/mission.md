# Mission — a red-first check that can never pass again once its fix is merged

Repo: ~/Projects/leadv2, `main` at `7de23af`. Work in a REAL lane worktree — confirm your
root appears in `git worktree list` before writing anything.

## Measured, not theorised

`bash plugins/leadv2/scripts/tests/run-core-offline.sh` on main right now:

```
suites passed=59 failed=3
  FAILED: deferred-GLM ladder (V3-GLM-LADDER-01)              <- known-foreign, not yours
  FAILED: fanout classifier/runner guard                       <- known-foreign, not yours
  FAILED: parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)   <- THIS ONE
```

Inside that third suite, exactly one assertion is red and eight are green:

```
[TEST] FAIL: contract red-first (pre=0 post=0)
[TEST] PASS: clean waiting result with unsatisfied deliverable classifies parked
[TEST] PASS: parked outcome carries continue next
[TEST] PASS: clean success stream replay is parked-shaped
[TEST] PASS: clean success with deliverable does not resume
[TEST] PASS: parked lane launches exactly one resume
[TEST] PASS: second parked exit does not loop
[TEST] PASS: second parked exit journals already_attempted
[TEST] PASS: positive control died-with-work resume remains green
[TEST] RESULT: pass=8 fail=1
```

Run standalone (`bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh`) the same
suite on the same commit gives `pass=9 fail=0`. So the difference is the harness context,
not the product.


## Base — pre-answered, do not ask

Your lane worktree is created from an older base and will be several commits behind `main`
(`7de23af`). **Merge `main` into your branch first. This is pre-approved — do not stop to ask.**
The files this mission targets only exist in their current shape on `main`; without the merge
you will be reading a tree that predates the three fixes landed today. A previous run of this
same mission ended with zero output because it stopped to ask this exact question.

## The defect

A red-first assertion claims "before this fix, this behaviour was RED". That is a statement
about a moment in history. Once the fix is merged to `main`, the "before" tree the check
constructs no longer lacks the fix, so `pre` passes, `pre=0 post=0`, and the assertion can
**never** be satisfied again. It is not detecting a regression — it is asserting an
unrepeatable fact about the past.

This is the same disease that blocked every lane tonight: a suite that is red for a reason
unrelated to product behaviour still fails the e2e gate and still blocks unrelated work.

## Do

Decide and implement ONE of these, and justify the choice in the report:

- **(a) Pin the baseline to a commit.** Make the red-first check construct its "pre" tree from
  the fix's parent commit (recorded at authoring time) rather than by reverting the working
  diff. Then the assertion stays meaningful forever, on any branch.
- **(b) Scope red-first to pre-merge only.** Make it a lane-time check that self-skips (SKIP,
  not FAIL) when the fix is already an ancestor of the tree under test, so it still guards a
  lane and stops lying on main.

Whichever you pick, apply it to the **mechanism**, not to this one suite: find every red-first
assertion in `plugins/leadv2/scripts/tests/` that has the same self-invalidating shape and fix
them together. One instance twice is a pattern — a census is part of this mission, and the
report must list every site you found and what you did with each.

Do not delete the assertion, do not lower it to advisory-without-explanation, and do not touch
the eight behavioural assertions.

## Off-limits
- Do not touch the two known-foreign suites; they are separate problems.
- Do not merge to `main` yourself — commit on your lane branch, the lead lands it.
- No `reset --hard` / `clean` / `stash`: this tree is shared with live sessions.

## Verify (FOREGROUND, explicit timeout, real pasted output)
1. `bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh` — standalone.
2. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Target: exactly
   TWO failures, the two known-foreign ones. If a third remains, name it.
3. Show that your fix still catches a genuine regression: break the parked-detect behaviour on
   purpose in a scratch copy, show the suite goes RED, restore it.

## Deliverable
`docs/handoff/RED-FIRST-SELF-INVALIDATES-01/report.md` — which option you chose and why, the
full census of self-invalidating red-first sites, the three verifications with pasted output,
`git diff --stat`. End with DELIVERABLE_COMPLETE.
