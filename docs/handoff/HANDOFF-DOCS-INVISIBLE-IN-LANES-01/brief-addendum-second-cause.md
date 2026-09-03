# HANDOFF-DOCS-INVISIBLE-IN-LANES-01 — second cause, found an hour after the first

Tracking a brief is **not sufficient**. A lane worktree is branched from `origin/main`, not from
local `main`, so a brief that is committed but not yet pushed is still invisible to the worker.

## Proof, measured 2026-09-03T04:36Z

The lead committed two briefs (`c341fc18`, `b5c96937`), dispatched both lanes, and deliberately
did not push — a push cancels an in-flight CI run through the workflow's concurrency group, which
had already cost one decisive run earlier that night.

Result:

    origin/main = 72546734          (one commit behind the briefs)
    lane worktree LANE-PLACEMENT-PIN-RED-01        → no docs/handoff/LANE-PLACEMENT-PIN-RED-01/
    lane worktree HANDOFF-DOCS-INVISIBLE-IN-LANES-01 → no docs/handoff/HANDOFF-DOCS-INVISIBLE-IN-LANES-01/

Both workers terminated within minutes. From the lane journal:

    arm_advance   task=8b995f4a from=codex to=sonnet reason=arm_produced_nothing
    review_gate   task=8b995f4a status=blocked reason=no_work terminal=no_work cause=empty_diff

Two lanes, two arms, zero output — purely because the specification was one push away.

## What this means for the fix

The fix has to make a brief reach the **worker**, not merely reach git. Options to weigh in the
report — the choice is yours, argue it:

- have the dispatcher stage the handoff directory into the lane worktree directly, independent of
  what has been pushed;
- have it branch from local `main` rather than `origin/main`;
- have it refuse to dispatch when the mission names a file the lane worktree does not contain.
  This one is attractive because it fails loudly instead of producing a silent empty round, and
  because it also catches a mission that names a path that never existed.

Whatever you choose, the failure mode to kill is the silent one. A worker that cannot find its
brief must not quietly return an empty diff and let the arm ladder burn a second arm on the same
missing file — that is what happened here, and from the outside it looked exactly like "the model
produced nothing", which is a very different and much more misleading diagnosis.
