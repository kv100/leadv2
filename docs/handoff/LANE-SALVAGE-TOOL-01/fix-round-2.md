# LANE-SALVAGE-TOOL-01 — round 2 report: main-moved case added

`leadv2-lane-salvage.sh` is unchanged this round, per the constraint. All edits are in
`plugins/leadv2/scripts/tests/test-lane-salvage.sh`: one new fixture helper
(`_install_main_move_hook`) and two new cases (9, 10).

## What case 9 / 10 do

Case 9 installs a `post-checkout` hook in the fixture's scratch repo that fires exactly once
(flag-file guarded) and, on that firing, commits directly onto `main` from main's own worktree.
`git worktree add` (inside `create_salvage_branch`) runs a checkout internally, so the hook fires
the instant the tool creates its throwaway salvage worktree — strictly after `MAIN_BEFORE` is
captured, strictly before `guard_main_untouched`'s first post-loop re-read. No sleep, no second
process: the tool's own git call is what advances main.

Asserted for case 9:
- non-zero exit + `main_moved` in the output
- the fixture actually moved main (case isn't vacuous)
- the tool's own printed `now=` matches the real post-hook main sha (the guard reports reality,
  not a fabricated mismatch)
- the throwaway salvage worktree is torn down on abort
- **measured, not asserted as correct:** the `salvage/LANE9` branch ref survives the abort. See
  "Finding" below — this is reported, not swept under a passing assertion.

Case 10 is the mirror: identical lane shape, hook not installed, main never moves. Same path
completes as `salvaged_green carried=1/1`. Without this mirror, case 9 could be satisfied by a
tool that simply always refuses.

## Finding — not in this round's scope, flagged for the lead

Measured live (`/tmp/probe-main-moved.sh`, and now case 9 itself): when `guard_main_untouched`
fires the abort, `_worktree_cleanup` (the `EXIT` trap) runs `git worktree remove --force "${WT}"`
but never `git branch -D "${SALVAGE_BRANCH}"`. The mission brief for this round assumed the abort
leaves no salvage branch behind; that is not what the tool does today. What's actually true:

- `main` itself is never touched by the tool (confirmed) — the guard's whole safety promise holds.
- The carry is **not** half-done — every planned commit made it onto `salvage/<lane>` before the
  post-loop guard check fires (there is no guard check inside the per-commit loop), so what's left
  behind is a *fully* carried branch, not a half-carried one.
- That branch is an orphan ref pointing at a base that is no longer main's tip. A rerun without
  `--force` hits `branch salvage/<lane> exists` at `create_salvage_branch` and refuses.

This is a real, minor gap (stale-branch cleanup on the main-moved path), not a safety violation —
main is never corrupted and no half-state is ever produced. I did not fix it: the brief for this
round explicitly forbids changing `leadv2-lane-salvage.sh`, and a fix belongs in its own
mutation-controlled round. I raised it via the async question channel
(`plugins/leadv2/scripts/ask-lead.sh`, question logged under
`docs/handoff/dispatch-e2e9bf0c/questions/`) with a reversible default (write the test against
true behavior, flag the gap, no tool change) and proceeded on that default after a 300s TIMEOUT —
no reply arrived.

## Ten consecutive suite runs

```
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
lane-salvage: pass=36 fail=0
```

(29 -> 36: +7 assertions across the two new cases, all green, all ten runs.)

## NC-1 — the round's required control (guard's fatal disabled)

Command:
```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-lane-salvage.sh \
  plugins/leadv2/scripts/leadv2-lane-salvage.sh \
  's|    _slv_fatal "main_moved before=${MAIN_BEFORE} now=${now} — salvage never touches main"|    : "no-op guard disabled NC1"|' \
  docs/handoff/LANE-SALVAGE-TOOL-01
```

Before this round: `MUTATION-CONTROL mutant_survived` (suite stayed 29/0 with the guard gutted).

After this round's case 9:
```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-salvage.sh file=plugins/leadv2/scripts/leadv2-lane-salvage.sh red_line=FAIL - case 9: expected non-zero exit + main_moved message, got rc=0: [slv] branch=salvage/LANE9 from main@2c81d5964faf (worktree /private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/lane-salvage.LANE9.XEUhjA) diff_hash=eb9315d72e4acc6b36ed6755ebd924c3c5f0c108b917c480825f462fc07004ef lane_diff_hash=ee03cd445d7119d51be529275ef087ceaa00308de795043cb7f783ee0e99595d
```

Artifact (`docs/handoff/LANE-SALVAGE-TOOL-01/mutation-control/*.txt`):
```
suite=plugins/leadv2/scripts/tests/test-lane-salvage.sh
file=plugins/leadv2/scripts/leadv2-lane-salvage.sh
anchor=s|    _slv_fatal "main_moved before=${MAIN_BEFORE} now=${now} — salvage never touches main"|    : "no-op guard disabled NC1"|
baseline_rc=0
mutated_rc=1
red_line=FAIL - case 9: expected non-zero exit + main_moved message, got rc=0: [slv] branch=salvage/LANE9 from main@2c81d5964faf (worktree /private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/lane-salvage.LANE9.XEUhjA)
diff_hash=eb9315d72e4acc6b36ed6755ebd924c3c5f0c108b917c480825f462fc07004ef
lane_diff_hash=ee03cd445d7119d51be529275ef087ceaa00308de795043cb7f783ee0e99595d
```

`baseline_rc=0` / `mutated_rc=1`, with a real `FAIL -` line — not a stack trace. Flipped as required.

## NC-2 — control on the new fixture helper (`_install_main_move_hook`)

The only new function body added to the suite's helpers this round. Mutation neutralizes the
hook's own commit onto main (so the hook installs but never actually advances main), which must
make case 9 fail on its own terms (fixture no longer moves main → the tool never sees a moved
main → completes normally instead of aborting).

Command:
```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-lane-salvage.sh \
  plugins/leadv2/scripts/tests/test-lane-salvage.sh \
  's|  git -C "\$MAIN_WT" commit -qam "main moved mid-salvage (test hook)"|  : "no-op hook disabled NC2"|' \
  docs/handoff/LANE-SALVAGE-TOOL-01
```

Result:
```
MUTATION-CONTROL ok suite=plugins/leadv2/scripts/tests/test-lane-salvage.sh file=plugins/leadv2/scripts/tests/test-lane-salvage.sh red_line=FAIL - case 9: expected non-zero exit + main_moved message, got rc=0: [slv] branch=salvage/LANE9 from main@29732f6af5dd (worktree /private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/lane-salvage.LANE9.OcLtP0) diff_hash=bb8c5ba339804b2bbf27ee010ef1217e97d945938634f7d8e1c448a4ce6521da lane_diff_hash=ee03cd445d7119d51be529275ef087ceaa00308de795043cb7f783ee0e99595d
```

Artifact:
```
suite=plugins/leadv2/scripts/tests/test-lane-salvage.sh
file=plugins/leadv2/scripts/tests/test-lane-salvage.sh
anchor=s|  git -C "\$MAIN_WT" commit -qam "main moved mid-salvage (test hook)"|  : "no-op hook disabled NC2"|
baseline_rc=0
mutated_rc=1
red_line=FAIL - case 9: expected non-zero exit + main_moved message, got rc=0: [slv] branch=salvage/LANE9 from main@29732f6af5dd (worktree /private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/lane-salvage.LANE9.OcLtP0)
diff_hash=bb8c5ba339804b2bbf27ee010ef1217e97d945938634f7d8e1c448a4ce6521da
lane_diff_hash=ee03cd445d7119d51be529275ef087ceaa00308de795043cb7f783ee0e99595d
```

`baseline_rc=0` / `mutated_rc=1`, real `FAIL -` line. No crash on either control.

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-salvage.sh && echo "bash -n tool OK"
bash -n tool OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-salvage.sh && echo "bash -n test OK"
bash -n test OK
```
(No Python files touched — `py_compile` not applicable.)

Working tree after both mutation-control runs: only `test-lane-salvage.sh` shows modified
(`git status --short`); `leadv2-lane-salvage.sh` is byte-identical to before this round — the tool
runs mutate a scratch snapshot only, never the real working tree.

## Constraints honored

- `leadv2-lane-salvage.sh` not touched.
- `tests/run-all.sh` not touched beyond what branch `a0cdd51b` already carried (one registration
  row, merged in — see commit list below).
- Nothing added to `tests/known-red-suites.txt`; no existing assertion weakened.
- No `reset --hard` / `clean` / `stash` / `worktree prune` used at any point.
- Not merged to main.

## Commits

- `88439cd1` — merge `worktree-LANE-SALVAGE-TOOL-01` (`ac05fe70`, `dc1ddccd`, `a0cdd51b`) into this
  worktree's branch, bringing in the tool + its existing 8-case suite (this worktree's branch had
  never had the tool at all — main hasn't merged it yet either).
- (this round's test-only commit, see developer.full.md for the exact sha)
