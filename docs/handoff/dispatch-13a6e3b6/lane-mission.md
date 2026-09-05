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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-13a6e3b6" "<question>" \
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