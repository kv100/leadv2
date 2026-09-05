# LANE-WRITESET-REGISTRY-01 — ONE TEST CASE. Nothing else. Commit it.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.

The M1 code fix is already committed at `963687c`. It is one line in
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`:

```
-  if [[ "${blocked_reason}" != "partial_diff" ]]; then
+  if [[ "${blocked_reason}" != "partial_diff" && "${blocked_reason}" != "writeset_drift_conflict" ]]; then
```

Without it, a lane blocked with `writeset_drift_conflict` fell into the landed-foreign
reclassification branch and had its cause overwritten, so the close reason lied about why the
lane stopped. The fix has NO test. That is your entire job.

## Do exactly this, nothing more
Add ONE case to `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh` (append to the
existing 6, do not restructure them) that:

1. Drives the real reclassification path in `leadv2-dispatch-product-close.sh` with
   `blocked_reason=writeset_drift_conflict`, faking only the layer below it.
2. Asserts the terminal cause STAYS `writeset_drift_conflict` and is not reclassified.
3. Also asserts the branch still fires for the reason it exists for — a `partial_diff` /
   landed-foreign lane must still be reclassified. A test that only checks the new exclusion
   would pass if someone deleted the whole branch.

## Proof — paste all of it
1. Revert the one-line fix in a SCRATCH copy (not the lane), run your new case, show it RED.
   That is the negative control: a test that cannot fail without the fix is not a test.
2. Run the full suite in the lane: all 7 cases green.
3. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows the suite selected.
4. `git commit` and paste `git status --porcelain` showing nothing modified under `plugins/`.
   The last three rounds all ended with work stranded uncommitted; an uncommitted test does
   not exist.

## Do not
Touch `leadv2-writes-overlap.sh` (frozen), restructure the existing 6 cases, change any
production file, or flip `LEADV2_WRITESET_ENFORCE`. If you find another bug, name it in your
reply — do not fix it here.

Return `PASS|FAIL|BLOCKED` + commit SHA + raw test output (both the RED and the GREEN).
