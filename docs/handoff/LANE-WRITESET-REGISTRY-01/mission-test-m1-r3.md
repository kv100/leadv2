# M1 TEST — make it anchor on a PATTERN, not on line numbers. One file, one function.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`
(now merged with `main`, HEAD `127674d`).
File: `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh`, function
`run_product_close_reclassify_wire`. Nothing else may change.

## The defect — in the TEST, not in the product code
The M1 guard is intact and correct at
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2393`:
`if [[ "${blocked_reason}" != "partial_diff" && "${blocked_reason}" != "writeset_drift_conflict" ]]`.

The test extracts that block with **hardcoded absolute line numbers**:

```
sed -n '2305,2387p' "$PRODUCT_CLOSE_SH"
```

Merging `main` moved the block (2306 → 2393), so the sed now grabs the wrong lines, the snippet
dies on a missing `review-gate.md`, and the case fails with `out1=[]`. The suite is 6/7 for this
reason alone. A test pinned to line numbers breaks on every unrelated edit above it — that is a
false alarm generator, and next time it will be read as "the guard broke".

## What to do
Replace the line-number extraction with a PATTERN-anchored one, exactly as the neighbouring
case `run_product_close_landed_foreign_wire` already does:

```
sed -n '/^if \[\[ "\${blocked_reason}" == "unscopable_diff" \]\]; then$/,/^fi$/p' "$PRODUCT_CLOSE_SH"
```

Anchor on the guard line itself (the `!= "partial_diff" && != "writeset_drift_conflict"` `if`)
through its matching `fi`. If the block needs setup lines that precede the `if`, anchor those by
pattern too — never by number. Add a guard that FAILS LOUDLY with a clear message if the pattern
matches nothing, so a future rename is reported as "pattern not found", never as a silent pass
or a confusing empty `out1=[]`.

Keep both assertions the case already makes:
1. `blocked_reason=writeset_drift_conflict` → NOT reclassified.
2. `blocked_reason=foreign_commit` (any other non-`partial_diff`) → STILL reclassified.

## Proof — paste all of it
1. Full suite in the lane: `Results: PASS=7 FAIL=0`. If you do not see that exact line, it
   crashed — fix that first.
2. Negative control in a SCRATCH copy (never the lane): delete the
   `&& "${blocked_reason}" != "writeset_drift_conflict"` half of the guard in
   `leadv2-dispatch-product-close.sh`, re-run — the M1 case must go RED. Paste it.
3. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows the suite selected.
4. `git commit`, then paste `git status --porcelain` showing nothing modified under `plugins/`.
   Six rounds in a row have left work uncommitted on this lane. Uncommitted work does not exist.

## Do not
Touch any production file — the guard is CORRECT, do not "fix" it. Touch the other 6 cases.
Touch `leadv2-writes-overlap.sh` (frozen). Flip `LEADV2_WRITESET_ENFORCE`.

Return `PASS|FAIL|BLOCKED` + commit SHA + both runs (RED and GREEN) verbatim.
