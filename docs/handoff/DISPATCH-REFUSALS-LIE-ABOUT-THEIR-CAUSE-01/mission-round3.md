# DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01 — round 3

Rounds 1 and 2 are **landed on `main`** and stay. Round 2's falsification of the prepass-tax
concern was correct and is accepted. This round is one failing assertion, found by the lead running
the suite **on main after the merge** — where it reads `pass=5 fail=1`, not the `6/0` the round-1
report recorded.

## The failure
```
FAIL: D2 untracked refusal mismatch rc=5:
[leadv2-dispatch-code] REFUSE mission: path=mission.md is present but untracked in lane
worktree=/private/var/folders/.../d2-repo/.claude/worktrees/lane
Remedy: git -C /private/var/folders/.../lane add mission.md && git -C /private/var/folders/.../lane commit -- mission.md
```

Read the refusal itself: it is **correct**. It names the state (`present but untracked`), names the
worktree, and hands over a runnable remedy. The behaviour this row exists to produce is working.

The assertion is what fails, at `test-dispatch-refusal-truth.sh:67-68`:

```bash
if [[ "${d2_rc}" == 5 ]] && grep -Fq 'present but untracked' "${d2_untracked}" \
  && grep -Fq "git -C ${D2_LANE} add mission.md && git -C ${D2_LANE} commit -- mission.md" "${d2_untracked}"; then
```

`${D2_LANE}` comes from `mktemp -d`, which on macOS returns `/var/folders/...`. The dispatcher
prints the **resolved** path, `/private/var/folders/...` — `/var` is a symlink to `/private/var`.
The fixed-string grep therefore compares two spellings of the same directory and loses.

That is why it can read 6/0 in one invocation and 5/1 in another: the two spellings agree or
disagree depending on how the path was obtained. **Verify this explanation before fixing it** —
print both values side by side in the failing run and show they are the same directory. If the real
cause is different, fix what you actually find and say so.

## The fix
Compare the paths as paths, not as strings: resolve both sides (the same way the dispatcher does)
before the comparison, or assert on a path-independent shape — the remedy names `git -C <the lane
worktree> add mission.md && git -C <same> commit -- mission.md`.

Keep all three parts of the assertion: the rc, the state phrase, and the remedy. Do not drop the
remedy check to make it pass — the remedy is half of what "a refusal names its cause" means here,
and an assertion loosened until it cannot fail is worse than the red it replaced.

The sibling check at `:74-78` (`D2 absent mission remains a distinct disk-absence refusal`) passes
and must keep passing: `absent` and `untracked` stay two distinguishable refusals.

## Acceptance
- `bash plugins/leadv2/scripts/tests/test-dispatch-refusal-truth.sh` run **from `main`** reads
  `pass=6 fail=0`.
- It reads the same when run from a lane worktree. State both, with the directory each was run
  from — this suite has already produced two different verdicts for the same code, so a single
  green is not evidence.
- The five previously passing cases still pass, by name.

## Negative controls — RUN both
1. Make the dispatcher stop printing the remedy → D2 goes RED. This proves the assertion still
   tests the remedy after your change, rather than having been widened around it.
2. Make the dispatcher answer the untracked case with the *absent* wording → the `:74-78` sibling
   goes RED. This proves the two refusals are still distinguishable.

Paste both red/green pairs. An unmatched mutation anchor is a test failure, never a silent skip —
and an anchor bound to an exact absolute path is precisely the rot this round is repairing, so do
not introduce another one.

## Off limits
- The refusal messages themselves and rounds 1-2 behaviour: landed and settled.
- Do not touch `--kind` at any call site — round 2 established that no change is needed there.
- Do not `git stash`, `git reset --hard` or `git clean`: this checkout is shared with live sessions
  in three other repos, and other sessions are editing files under `plugins/leadv2/tests/` right
  now.

## Report
Append `## Round 3` to `docs/handoff/DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01/report.md`: the
confirmed cause with both path spellings printed, the fix, the two run locations with their
verdicts, and both controls. End with `DELIVERABLE_COMPLETE`.
