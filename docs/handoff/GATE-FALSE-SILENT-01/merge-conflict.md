# Mission — land `worktree-2d8a2849` on main; the conflict is in one file

Repo: ~/Projects/leadv2. Work in a REAL lane worktree — verify with `git worktree list` that
your root is registered before you write anything. Today's incident happened because a lane
root was a bare directory with no `.git`, so `git -C` walked up into the canonical checkout
and a worker wrote plugin code straight into it.

## State, measured

`main` is at `b680643`. Two of the four diffs in this chain are already merged:

```
78bcb9b  merge(LANE-ROOT-NOT-A-WORKTREE-01)   gate refuses to grade a non-worktree lane root
b680643  merge(WORKER-PARKED-ON-BG-01)        parked-on-background-job exit is resumable
```

Branch `worktree-2d8a2849` (head `9ec61af`) carries the third: GATE-FALSE-SILENT-01.
`git merge --no-ff worktree-2d8a2849` was attempted by the lead and aborted cleanly:

```
CONFLICT (content): plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
Auto-merging               plugins/leadv2/scripts/tests/run-core-offline.sh   (resolved itself)
```

All three lanes edited `leadv2-dispatch-product-close.sh`, which is why it conflicts.

## What each side means — resolve by intent, not by hunk

- **main's side** now contains the `lane_root_not_a_worktree` verdict and the parked-worker
  outcome plumbing. Both must survive.
- **The branch's side** contains `_pc_lane_commits_ahead` plus the prove-zero / genuinely-unknown
  split inside `pc_silent_arm_probe`: a lane whose worktree HEAD never moved is provably silent;
  a lane whose base cannot be resolved is *unknown* and must NOT be called silent (it emits
  `silent_probe_base_unresolved`). Both halves of that distinction must survive.

Resolve so all three behaviours coexist. Do not drop a verdict to make the merge simple, and do
not re-implement either side from scratch.

## Verify (FOREGROUND, explicit timeout, real pasted output)

These were green on the branch before the merge — lead-run, not worker-claimed:

1. `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh` — 5 passed (C5 green).
2. `bash plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` — 15 passed
   (Case E green; Cases F/G are the prove-zero split).
3. `bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` — 12 passed.
4. `bash plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh` — 4 red-to-green, and
   `bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh` — 9 passed. These two are
   main's side; a resolution that breaks either is wrong.

Then `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code. Exactly TWO
failures are known-foreign and NOT yours: `deferred-GLM ladder (V3-GLM-LADDER-01)` and
`fanout classifier/runner guard` (the latter fails because `leadv2-fanout.sh:52` sources a file
absent from the harness's private HOME). A third failure is yours: name it and fix it.

## Off-limits
- Do not merge to `main` yourself. Produce the resolved commit on your lane branch; the lead lands it.
- Do not touch the canonical checkout `~/Projects/leadv2` — work only inside your worktree.
- No `reset --hard` / `clean` / `stash` anywhere: this tree is shared with other live sessions.

## Deliverable
`docs/handoff/GATE-FALSE-SILENT-01/merge-report.md` — how you resolved each conflicting hunk and
why all three behaviours survive, the six verifications with pasted output, `git diff --stat`
against `b680643`. End with DELIVERABLE_COMPLETE.
