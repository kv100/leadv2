# LANE-PLACEMENT-PIN-RED-01

`test-lane-placement-pin.sh` is red on `main` and is now the only thing standing between this repo
and a green CI gate (`SD-CI-REQUIRE-STATUS-CHECKS-01`). It got worse in tonight's freepool merge,
but it was **already** red before it — read both halves below before touching anything.

## Measured, with a fair comparison

Both runs by the lead on this Mac, same suite, same 200s+ budget (an earlier 110s run was
discarded as an unfair comparison — a timed-out run invents failures):

    a28b16a2  (before the freepool merge)   [LANE-PLACEMENT-01] passed=23 failed=4
    72546734  (main, after it)              [LANE-PLACEMENT-01] passed=14 failed=13

So there are **two separate problems**, and they must not be conflated:

**(1) Four failures are pre-existing**, all of one shape — `P-h(a)`, `P-h(b)`, `P-h(g)`,
`P-h(g2)`: "prompt pin line MISSING". These were red before tonight and nobody noticed, because
`run-all --scope changed` only selects this suite when `leadv2-dispatch-code.sh` changes. That is
the same blind spot `LAST-LINUX-RED-FAST-NAMES-01` hit from the other direction.

**(2) Nine failures are new since the freepool merge (`2062dbcf`)**, all of two shapes:

    FAIL: P-a / P-b / P-g: dispatch exited 3 (or 4)
    FAIL: P-a / P-b / P-g: worker cwd='' != RESUME='…/.claude/worktrees/RESUME-ME-01'
    FAIL: D3: ensure-created plan missing (rc=4, cwd='')

## What is NOT yet known — do not repeat the lead's shortcut

The lead probed the real repository with a resolve-only dispatch
(`--no-spawn`, `LEADV2_DISPATCH_SPAWN=0`) and it ran cleanly end to end, including the freepool
merge's new step: `protection_derived by=router … writes=<none> write_class=unknown
writes_protected=1`, then `route_resolved … arm=codex`, then a clean rollback.

**That proves resolution, not placement.** The failing assertions are about `--resume-lane` /
`--worktree` placement and the worker's pinned cwd, which the probe never exercised. So "it is
only the fixture" is a hypothesis, not a finding, and it is exactly the comforting kind. Your
first job is to decide it with evidence:

- If the harness is genuinely out of date with the new write-set derivation, say precisely what
  the fixture lacks and fix the fixture — without weakening what it asserts.
- If placement or the cwd pin is actually broken for a resumed lane, that is a production bug on
  `main` and it outranks everything else in this brief. Say so plainly and fix that first.

An `rc=3` is "arm=opus, lead judgment, not auto-dispatched" and `rc=4` is "spawn failed"; those
are different causes and the report must not merge them.

## Definition of done

1. `test-lane-placement-pin.sh` green — all 27, not just the nine. If you conclude a pre-existing
   `P-h` assertion is itself wrong, argue it in the report and change the assertion deliberately;
   do not quietly leave four reds behind.
2. State, with evidence, whether (2) was a fixture gap or a real placement bug. If real: name the
   file:line, and say whether any lane dispatched between `2062dbcf` and the fix could have run in
   the wrong directory.
3. A negative control per cause you claim fixed: name the mutation, show red, revert, show green.
4. Green on macOS and in a Linux container, exit codes pasted.
5. Nothing added to `tests/known-red-suites.txt`.
6. Answer the exposure question that `LAST-LINUX-RED-FAST-NAMES-01` also raised: how many suites
   are selected only when one specific file changes, and so can sit red for weeks unnoticed? A
   count and the list is enough — the fix for that is a separate task.
7. Commit in this lane before you finish.

Off limits: `main`, the allow-list, weakening assertions, and reverting the freepool merge — its
own acceptance is proven and its write-set derivation is wanted.
