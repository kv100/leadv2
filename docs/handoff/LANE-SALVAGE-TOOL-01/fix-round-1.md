# LANE-SALVAGE-TOOL-01 — round 2: the tool's central safety promise has no test behind it

LANE_WRITES: plugins/leadv2/scripts/tests/test-lane-salvage.sh, docs/handoff/LANE-SALVAGE-TOOL-01/

The tool itself is good and I am not asking you to change it. Branch
`worktree-LANE-SALVAGE-TOOL-01` at `a0cdd51b`, suite `29 passed, 0 failed` over **ten consecutive
runs**, zero conflicts against main by `git merge-tree`. Keep all of it.

## The gap — measured, not suspected

`guard_main_untouched()` is the promise the whole tool rests on: it re-reads `main` and aborts if it
moved. I disabled its only consequence through the real tool:

```
bash plugins/leadv2/scripts/leadv2-mutation-control.sh \
  plugins/leadv2/scripts/tests/test-lane-salvage.sh \
  plugins/leadv2/scripts/leadv2-lane-salvage.sh \
  's|    _slv_fatal "main_moved before=${MAIN_BEFORE} now=${now} — salvage never touches main"|    : "no-op guard disabled NC1"|' \
  docs/handoff/LANE-SALVAGE-TOOL-01

MUTATION-CONTROL mutant_survived
```

The suite stayed **29/0** with the guard gutted. Eight cases assert "main untouched" and every one of
them passes for free: they compare `main`'s sha before and after a run in which nothing ever tries to
move `main`. The assertion is not tautological — it would catch a tool that moved main itself — but
the guard it appears to defend is the one that catches **someone else** moving main mid-salvage, and
no case creates that situation.

That matters here more than usual. Salvage runs while other lanes are live; a concurrent lead
committing to main during a salvage is not a hypothetical, it is the normal state of this machine.

## Your task

Add the case the suite is missing: **main moves during the salvage run**, and the tool must refuse.

- Set up a lane with carryable work, start the salvage, and make `main` advance between
  `MAIN_BEFORE` being captured and `guard_main_untouched` running. A commit to `main` from the
  fixture's own scratch repo is enough — no concurrency primitives, no sleeps.
- Assert the tool **aborts** with the `main_moved` message and a non-zero exit, and that it did
  **not** leave a salvage branch or a half-carried commit behind.
- Assert the mirror as well: when main does not move, the same path still completes and carries the
  work. Without the mirror the case could be satisfied by refusing always.

## Prove it

- Ten consecutive suite runs, all ten count lines pasted. Ten, not five.
- **The NC-1 control above must flip from `mutant_survived` to `baseline_rc=0` / `mutated_rc=1`**,
  with the literal red line. That flip is the deliverable of this round.
- One further control per function body you touch in the suite's helpers, same shape.
- A mutant that reddens the suite by **crashing** is not a control. That happened on another lane
  tonight (`JSONDecodeError`): it reads exactly like a pass and was discarded and redone. If your
  mutant produces a stack trace instead of a failed assertion, fix the anchor.

## Constraints

- Do **not** change `leadv2-lane-salvage.sh`. The tool is correct; you are adding the assertion that
  proves it. If you believe the tool must change, stop and say so with evidence instead.
- Do not touch `tests/run-all.sh` beyond what the branch already does (it adds one registration row).
- Do not touch `main`, `tests/known-red-suites.txt`, or `docs/leadv2/` from inside the lane.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune` — the tree is shared and live lanes
  stand next to yours.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened.
- Do not merge to main. Leave the branch green with a report.

## Report

Ten suite count lines, the NC-1 pair with its red line, any further control pairs, and the commit
shas. Nothing else.
