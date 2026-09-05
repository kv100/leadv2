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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-4a77ec35" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.