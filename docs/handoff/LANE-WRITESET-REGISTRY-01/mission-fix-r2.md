# LANE-WRITESET-REGISTRY-01 — FIX ROUND 2. One Medium left. Small, surgical, then done.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.
Plan: `docs/handoff/LANE-WRITESET-REGISTRY-01/context.yaml` (D1–D9).
Review round 2 verdict: `docs/handoff/dispatch-533daa27/review-gate.md`.

## State — verified by the lead, do not re-derive
Round-1's four High findings are fixed and now COMMITTED (`7632e84`, `ffbb5af`). The suite is
6/6 green, the declared negative control still reddens exactly the three overlap cases, and
`LEADV2_SUITE_SHARDS_DUMP=1` shows the suite selected at `shard=3 idx=19`. The round-2 review's
single High ("H1 not fixed") was a stale-diff artifact: `_lv2_ws_pending` existed only in the
working tree at review time; it is in `HEAD` now. Do not re-open it.

## The one thing owed — M1
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` ~:2306.

After the H4 narrowing, `writeset_drift_conflict` now falls into the `!= partial_diff`
reclassification branch and has its cause OVERWRITTEN, so a lane that committed cleanly gets
stamped with the wrong terminal cause. H4 stopped the escape from turning a BLOCK into a pass;
this is the mirror bug one layer down — the block survives but is relabelled, which makes the
close reason lie about why the lane stopped.

Fix it so `writeset_drift_conflict` keeps its own cause end to end. Read the surrounding
reclassification branch first and say in one line which condition you changed and why that
cannot swallow the other reasons it was written for.

## Proof required — do not report green without it
1. A new suite case asserting the terminal cause of a drift-conflicted lane is
   `writeset_drift_conflict` and NOT the reclassified value. It must FAIL against the current
   code — run it before your fix and paste the RED, then paste the GREEN after.
2. `bash plugins/leadv2/scripts/tests/test-writeset-admission-block.sh` — all cases green,
   pasted. The existing 6 must not regress.
3. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows selection.
4. **COMMIT everything before you finish, and paste `git status --porcelain` showing no
   modified files under `plugins/`.** This is not boilerplate: the previous round left the
   entire H1 fix uncommitted, the review read `HEAD`, and reported the fix missing. An
   uncommitted fix does not exist.

## Constraints unchanged
`leadv2-writes-overlap.sh` frozen. `test-writes-overlap.sh` append-only. `LEADV2_WRITESET_ENFORCE`
stays `warn` by default. `LEADV2_WRITES_CONFLICT_NOTIFY=0` must never turn the gate green.
Never edit through a consuming repo.

Return `PASS|PARTIAL|FAIL|BLOCKED` + changed paths + commit SHA + raw test output.
