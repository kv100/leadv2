# WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01 — round 2: the failure branch runs and nothing checks it

LANE_WRITES: plugins/leadv2/scripts/tests/test-lane-worktree-registry-pointer.sh, docs/handoff/WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01/

Work on branch `worktree-WORKTREE-CREATION-RESURRECTS-THE-FROZEN-REGISTRY-01`, on top of what is
already there. **Do not change `leadv2-lane-worktree.sh`** — the fix is correct; what is missing is
the assertion that proves its most important promise.

## What round 1 got right — keep every bit of it

Verified by the lead by running it, not from the report:

- suite `test-lane-worktree-registry-pointer.sh` — **7 passed, 0 failed, ten consecutive runs**, rc=0
  every time;
- **both creation sites are covered separately**, and this is the thing that mattered most. Removing
  the `degrade_frozen_registry_copy` call at line 295 (attach-to-existing) reddens **exactly one**
  assertion, case 4, its named one. Removing it at line 288 (fresh branch) reddens cases 2 and 2b and
  leaves case 4 green. Neither mutation bleeds into the other site's case — the suite genuinely tests
  two places rather than one place twice;
- cases 2 + 2b share a cause (no call → no symlink AND no skip-worktree flag), so 2b is not
  independent evidence of anything. That is expected, not a defect;
- the fix resolves the live path through `leadv2-state-path.sh` rather than composing it, and case 5
  proves a branch that never tracked `active.yaml` is left alone (no phantom file).

## The gap — measured, not suspected

The fix promises that when the live path cannot be resolved, the frozen copy is **destroyed** rather
than left looking authoritative:

```
printf 'NOT-A-REGISTRY: … ' > "$frozen" 2>/dev/null || rm -f "$frozen" 2>/dev/null
```

The suite contains the string `NOT-A-REGISTRY` **zero times in an assertion** — one occurrence in the
file, in a header comment at line 18.

Forcing the failure branch (single-site mutation, `sp_bin` pointed at a nonexistent path) shows the
branch really executes — its stderr appears in the output:

```
FAIL: 2:  got symlink target='' … (stderr: … could not resolve live active.yaml path … -- neutralizing frozen copy …)
FAIL: 2b: expected skip-worktree flag 'S', got 'H'
FAIL: 4:  got symlink target='' … (same stderr)
red count: 3
```

Every one of those reds says only **"there is no symlink"**. If the neutralization itself silently
failed — the `printf` redirect fails and the `rm -f` also fails, leaving the original stale YAML in
place — this suite would print **exactly the same three lines**. The two outcomes are
indistinguishable, and they are opposites: one leaves an obvious non-registry, the other leaves a
frozen copy that reads as the registry.

That matters more here than anywhere else on this lane. Twelve worktrees carry a frozen copy today;
seven answer zero and five answer a plausible stale number, and **the five are worse**, because a
zero invites a second look and a plausible number does not. The neutralization is the only thing
standing between a resolver failure and a sixth plausible liar.

## Your task

Add the assertion the suite is missing: **after a forced resolver failure, the file at
`docs/leadv2/active.yaml` in the new worktree is not usable as a registry.**

1. Force the failure inside the fixture — do not mutate the product to create it. Make
   `leadv2-state-path.sh` unresolvable for one case only (an unreadable or absent copy in the
   fixture's own script dir, a `script_dir` the fixture controls). Say in a comment how you forced it
   and why that is the same condition production would hit.
2. Assert the **post-state of the file**, not a message: either its content matches the sentinel, or
   the file does not exist. Never assert on the stderr text alone — a warning that is printed while
   the file survives is precisely the shape being ruled out.
3. Assert it for **both** creation sites, as the existing cases do.

## Prove it

- **A control that reddens ONLY the new assertion.** Neuter the neutralization in
  `leadv2-lane-worktree.sh` (make the `printf`/`rm` line a no-op, single site, inside the body) and
  show the new case goes red while every other case keeps its round-1 result. If cases 2/2b/4 also
  redden, your fixture is forcing the failure globally instead of for one case — narrow it.
- **Read the mutated line back before trusting the run.** A mutation can change the file's sha256 and
  still be inert: this cost a whole verification round on this machine today when a `perl`
  replacement interpolated `$link_name` as its own undefined variable and inserted
  `[[ -L "" ]] && return 0`. Print the line.
- **Before believing any zero, show the same probe returning non-zero.** Four layers of blindness
  stacked in one verification today with zero defects in the code under test, and only a positive
  control on the instrument caught it.
- **Scratch worktrees go under `/private/tmp`, never `/tmp`.** On macOS `/tmp` is a symlink to
  `/private/tmp` and `run-all.sh`'s `root_escape` guard kills any run from a tree under a symlink
  with `rc=2` before it selects anything — which reads exactly like "the suite was not selected".
- **Ten consecutive runs**, all exit codes pasted. A disagreement between runs IS the finding.
- Restore the file after every mutation and show the restored run is green.

## Constraints

- Do not change `leadv2-lane-worktree.sh` except transiently for a control, restored afterwards.
- Do not weaken any existing case.
- Do not touch `tests/run-all.sh` (declare triggers in the suite with a `# run-all-triggers:` line —
  note that the walker for those declarations is **not on `main` yet**, it lands with the suite-map
  branch), `tests/known-red-suites.txt`, `main`, or `docs/leadv2/`.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune` — the tree is shared and live lanes
  stand next to yours. Remove any scratch worktree you create with `git worktree remove`.
- Commit incrementally: the e2e gate times out at 900s and has already parked one lane today on the
  threshold between finished and committed.
- If any instruction here rests on a false premise, stop and say so with the measurement. That is a
  complete and welcome answer.
- Do not merge to main. Leave the branch green with a report.

## Report

The new case's name, the control's `baseline_rc` / `mutated_rc` / `restored_rc` triple with the
literal red line and the full list of red lines under it, the ten count lines, and the commit shas.
Nothing else.
