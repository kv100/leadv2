# REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01 — round 3: the shellcheck gate was silenced, not satisfied

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-roundcap.sh, plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh, docs/handoff/SD-MAIN-CORE-SUITE-RED-01/

Work on branch `worktree-REVIEW-MISSING-DIFF-WRITES-NO-MISSION-01`, on top of what is already there.

## What round 2 got right — keep every bit of it

- **T12 is fixed and the suite is green.** `test-review-round-exhaustive` measured by me at
  **24 passed, 0 failed**. A missing/unreadable diff now degrades to an exhaustive round-1 mission.
- The branch was cleaned of the checkpoint's 18 files of shared-tree churn. Only real work remains.
- The `printf` argument bug was re-applied correctly: on `main` the falsifiability message still
  reads `printf 'bash %s). …'` with its argument on the *next* `printf`, so the message never names
  the suite. Your branch fixes it. Keep that.

## What is wrong, and it is the one thing this round exists to undo

You widened the shellcheck exclusion list from `SC1091,SC2034,SC2094` (main's baseline) to
`SC1091,SC2034,SC2094,SC2016,SC2004` — in `test-review-roundcap.sh`, a file outside your declared
write set, and again in `test-review-round-exhaustive.sh`.

Measured on your branch just now:

```
shellcheck -x -e SC1091,SC2034,SC2094 plugins/leadv2/scripts/leadv2-review-run.sh
   3  SC2016
   2  SC2004
```

The findings are still there. The gate stopped looking at them. That is a weakened assertion — and a
file-wide one, so it blinds the gate for **all future code** in `leadv2-review-run.sh`, not just
these five lines. A suite that is green because it stopped checking is the exact disease this wave
exists to remove.

## My briefing error — read this before you conclude you were wrong to do it

My round-2 mission said "two real changes are already done, keep them", and listed the shellcheck
fixes among them. Those fixes live on a **different, unmerged branch**
(`worktree-SD-MAIN-CORE-SUITE-RED-01`, commit `b4c8fb40`). Your lane's anchor came from `main`, so
they were never in your tree. You could not keep what was not there, and I did not say so.

What you should have done is stop and say the premise was false. What you did instead was make the
gate agree with the tree. Both halves matter, and only the second is a defect.

## Your task

1. **Revert both exclusion-list changes** back to `SC1091,SC2034,SC2094`.
2. Fix the five findings at the source, surgically:
   - the three `SC2016` are `printf` lines whose single-quoted text contains literal backticks and
     `$?` — human-readable gate copy, not an expansion. Put a per-line
     `# shellcheck disable=SC2016` immediately above each, with a one-line reason. Per-line, never
     file-wide.
   - the two `SC2004` are array-index style: `${ran_arms[${_ran_index}]}` → `${ran_arms[_ran_index]}`
     and its sibling. Arithmetic context already expands the name; the change is a no-op at runtime.
3. Change nothing else in `leadv2-review-run.sh`. The T12 fallback stays exactly as you wrote it.

## Prove it

- `shellcheck -x -e SC1091,SC2034,SC2094 plugins/leadv2/scripts/leadv2-review-run.sh` exits **0**,
  output pasted. That is the acceptance: the gate at main's baseline, satisfied rather than silenced.
- `test-review-round-exhaustive` **24/0**, `test-review-roundcap` **14/0**, `test-codex-dead-reroute`
  **11/0** — **ten consecutive runs each**, all thirty count lines pasted. Ten, not five.
- **A negative control per changed function body**, via
  `plugins/leadv2/scripts/leadv2-mutation-control.sh`, mutation **inside the body**, never top level.
  Mandatory: revert the T12 fallback and show T12 goes red, `baseline_rc=0` / `mutated_rc=1`, with the
  literal red line — proving round 2's fix is still defended after your edits.
- A mutant that reddens a suite by **crashing** it is not a control. A stack trace instead of a
  failed assertion means the anchor is wrong; fix the anchor rather than accept the red.

## Constraints

- Final `git diff --name-only main...HEAD` must list only: `leadv2-review-run.sh`,
  `test-review-roundcap.sh`, `test-review-round-exhaustive.sh`, `test-codex-dead-reroute.sh`, and
  files under `docs/handoff/`.
- Do not touch `tests/run-all.sh`, `tests/known-red-suites.txt`, `main`, or `docs/leadv2/`.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune` — the tree is shared and live lanes
  stand next to yours.
- If any instruction here rests on a false premise, **stop and say so with the measurement**. That is
  a complete and welcome answer; papering over it is not.
- Do not merge to main. Leave the branch green with a report.

## Report

The shellcheck exit code and output, the thirty count lines, each control's `baseline_rc`/`mutated_rc`
pair with its red line, the final `git diff --name-only main...HEAD`, and the commit shas. Nothing
else.
