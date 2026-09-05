# M1 TEST CASE — round 2. The previous arm added a CALL without the FUNCTION and broke the suite.

Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27`.
Target file: `plugins/leadv2/scripts/tests/test-writeset-admission-block.sh` (currently 6/6 GREEN;
the lead reverted the previous arm's breakage). Do not restructure the existing 6 cases.

## What went wrong last time — do not repeat it
The arm appended `run_writeset_drift_conflict_wire "$f"` to `main()` and never defined the
function. The suite died with `command not found` at line 204 and printed no Results line. Both
halves — the function AND its call — must land together, and you must RUN the suite before you
commit.

## What to test
`leadv2-dispatch-product-close.sh` has a reclassification branch guarded by
`if [[ "${blocked_reason}" != "partial_diff" && "${blocked_reason}" != "writeset_drift_conflict" ]]`.
The second condition is the M1 fix (commit `963687c`). Without it a lane blocked with
`writeset_drift_conflict` had its cause overwritten, so the close reason lied.

Assert BOTH directions, or the test is worthless:
1. `blocked_reason=writeset_drift_conflict` → the cause survives, is NOT reclassified.
2. `blocked_reason=<some other non-partial_diff reason>` → the branch STILL fires. A test that
   only checks the exclusion would pass if someone deleted the whole branch.

## Copy the shape that already works
`run_product_close_landed_foreign_wire` at ~:159 of that suite is the exact pattern for driving
this file's real branches: it `sed`-extracts the live block from `$PRODUCT_CLOSE_SH` into a temp
file, stubs `emit` / `_dl_note` / `_stamp_review_terminal` as no-ops, sources the snippet under
the env var it keys on, and greps the resulting `review-gate.md` / echoed marker. Follow it.
Name your function `run_product_close_reclassify_wire`, define it next to that one, and add its
call to `main()` with its own sandbox var (extend the `local a b c d e f` list and the trap).

## Proof — paste all of it, no exceptions
1. Run the suite in the lane: **7 cases, all green, with the `Results: PASS=7 FAIL=0` line
   visible.** If you do not see that line, the suite crashed — fix it before anything else.
2. Negative control: in a SCRATCH copy (not the lane), revert the `&& ... != writeset_drift_conflict`
   half of the condition, run your new case, show it RED. A test that cannot fail without the
   fix is not a test.
3. `LEADV2_SUITE_SHARDS_DUMP=1 bash plugins/leadv2/scripts/tests/run-core-offline.sh | grep write-set`
   still shows the suite selected.
4. `git commit`, then paste `git status --porcelain` showing nothing modified under `plugins/`.
   Five rounds in a row have ended with work stranded uncommitted. Uncommitted work does not exist.

## Do not
Touch any production file. Touch `leadv2-writes-overlap.sh` (frozen). Restructure the existing
6 cases. Flip `LEADV2_WRITESET_ENFORCE`. If you find another bug, name it in your reply instead
of fixing it.

Return `PASS|FAIL|BLOCKED` + commit SHA + both test runs (RED and GREEN) verbatim.
