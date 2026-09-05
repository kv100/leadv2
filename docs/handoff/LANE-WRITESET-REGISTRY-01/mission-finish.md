# LANE-WRITESET-REGISTRY-01 — FINISHER (round 3). Core is done. Prove it and land it.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.
Binding plan: `docs/handoff/LANE-WRITESET-REGISTRY-01/context.yaml` (D1–D9, 9 steps,
verification.live_signal, test_plan). Read it. The full original mission is `mission.md` beside it.

## State of the lane — verified by the lead, do not re-derive
Steps 1–7 are IMPLEMENTED and committed at `09a5fca` (an auto-checkpoint), plus one uncommitted
doc line. The lead has already confirmed the crux (D3) is correct: in
`plugins/leadv2/scripts/leadv2-active-registry.sh` the candidate/incumbent intersect runs
INSIDE the same flock as the append, with `sys.exit(5)` for a real conflict, `sys.exit(6)` for
`writeset_unknown` under `LEADV2_WRITESET_ENFORCE=block`, and the `LEADV2_WRITESET_UNKNOWN`
line under the default `warn`. Do NOT rewrite that. Your job is the unfinished tail.

## What is owed — this is the whole task, nothing else
1. **Step 8** — `plugins/leadv2/scripts/leadv2-phase8-close.sh`: immediately BEFORE
   `leadv2_active_unregister "${TASK_ID}"` (~:559) read the closing row's `writes` and compute
   intersecting alive peers via `leadv2-writes-overlap.sh` in notify mode (that script is
   FROZEN — read-only, do not modify it). AFTER the unregister, for each peer write (a) a
   journal finding on the PEER's task id and (b) a line to `docs/leadv2/writeset-notify.log`.
   Order is load-bearing: the closing lane's `writes` dies with its row. Wrap the whole block
   so it can never fail a close (`|| true`, mirroring the non-blocking style at ~:560-566).
2. **Step 9** — create `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh` per
   `test_plan.new_suite`, AND add its selection row to the suite array in
   `plugins/leadv2/scripts/tests/run-core-offline.sh` (~:263-287). Prove selection by running
   the runner and showing the suite's label in its own output. A suite CI never selects is
   worth nothing — this repo has been burned by exactly that.
3. **Run `verification.live_signal` from the plan, verbatim.** Paste the raw output. It passes
   only if all three hold: `rc=5`, the line `writeset conflict: other=LANE-A`, and LANE-B was
   NOT appended to the sandbox active.yaml (that last one is what proves atomicity).
4. **Negative control**, declared in `test_plan.negative_control`: flip the overlap predicate
   `_lv2_ws_overlaps` so it never matches — INSIDE the function body, in a scratch worktree —
   and show the new suite goes RED. Paste the output. A top-level insert reddens everything
   for the wrong reason and reads as a pass; do not do that.
5. **Resolve the scope deviation**: `leadv2-dispatch-product-close.sh` (+35 lines) is not among
   the plan's 9 steps. Either justify it in one line against D8/step 8, or revert it. Do not
   leave an unexplained file in the diff.
6. **Commit** the whole lane as one clean commit and report the SHA.

## Constraints that still bind
- `leadv2-writes-overlap.sh` and `test-writes-overlap.sh` are off-limits except APPEND-ONLY
  test cases; its 5 existing cases are the fanout regression baseline.
- `LEADV2_WRITES_CONFLICT_NOTIFY=0` must never be able to turn the admission gate green (D4).
- `LEADV2_WRITESET_ENFORCE` stays defaulted to `warn`. Do not flip it to `block`.
- Never edit through a consuming repo (persona-engine / m3-market / respiro-ios) — symlinks.

## Budget
You are the finisher. If something cannot be proven, say so in plain words and return
`PARTIAL` naming exactly what is proven and what is not. Never return a green claim you did
not run — an unrun test reported as passing is the one failure this task exists to prevent.

Return `PASS|PARTIAL|FAIL|BLOCKED` + changed paths + commit SHA + raw test output.
