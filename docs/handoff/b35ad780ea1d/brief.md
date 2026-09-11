# LANE-MERGE-SILENTLY-REVERTS-MAIN-01

Wave B0. Files: `plugins/leadv2/scripts/leadv2-merge-safety-gate.sh` (+ its callers).

## Defect
A lane branched BEFORE someone else's merge silently DELETES what landed on main
after its branch point, when it is merged. Five occurrences in one day; the only
thing that ever caught it was a human eyeballing the diff.

## Known trap (read before writing the check)
`git log main..branch` shows main's newer files as DELETIONS — that is the normal
appearance of an old branch, not proof of a revert. The only sound test is to diff
the **merge TREE** against main: compute the would-be merge result and assert that
no path present in main disappears or regresses. A difference has no direction
until you date it.

## Deliver
1. A gate function that, given a lane branch and main, computes the merge tree
   (`git merge-tree`, or a scratch-worktree trial merge) and REFUSES with a
   non-zero code + a named path list when the merge would remove or revert a path
   that main gained after the branch point.
2. Wire it into the landing path so a merge cannot proceed past a refusal.
   Fail CLOSED: if the check itself cannot run (no origin/main, no merge base),
   refuse — never assume clean.
3. Suite: `plugins/leadv2/scripts/tests/test-merge-safety-reverts-main.sh`,
   building a real scratch repo that reproduces the five-case shape.

## Negative control (declare it, and RUN it)
Mutation: make the gate return "clean" unconditionally inside its body.
The suite MUST go red. Paste output to `docs/handoff/b35ad780ea1d/round1-red.txt`.

## Off limits
Do not touch `leadv2-lane-salvage.sh` — another lane owns it this round.

## Done
- suite green clean / red mutated, both pasted
- the gate refuses on a synthetic revert case AND on an unresolvable base
