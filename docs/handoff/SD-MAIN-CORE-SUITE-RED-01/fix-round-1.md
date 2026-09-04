# SD-MAIN-CORE-SUITE-RED-01 — round 2: a missing diff file produces NO review mission at all

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh, docs/handoff/SD-MAIN-CORE-SUITE-RED-01/

## What is already done — keep it, do not redo it

The checkpointed branch `worktree-SD-MAIN-CORE-SUITE-RED-01` (`0182ced5`) carries two real changes
and I verified both by reading them, not by trusting the commit:

- `leadv2-review-run.sh` — shellcheck disables plus a **real bug fix**: the "suite falsifiability
  undetermined" message had its `%s` in one `printf` and its argument on the next one, so the message
  told the worker to run a suite and never named it. Correct fix, keep it.
- `test-codex-dead-reroute.sh` — the source-line grep now accepts the symlink-safe
  `${_REVIEW_REROUTE_NOTE_SH}` form as well as the literal `${SCRIPT_DIR}` one. I checked the product
  before accepting this: `leadv2-dispatch-product-close.sh:2999-3002` genuinely resolves the lib
  through that fallback variable and calls `leadv2_review_reroute_note`. The relaxation asserts the
  invariant ("the shared lib is sourced and called") instead of one path expression, and it still
  requires the lib filename and the call. Keep it.

Measured now, on the branch: `test-codex-dead-reroute` **11/0**, `test-review-roundcap` **14/0**,
`test-review-round-exhaustive` **PASS=23 FAIL=1**.

## The remaining red is a product defect, and I localised it

`T12 missing diff file -> exhaustive, no sidecar, stderr` fails on its **first** assertion. I
instrumented a scratch copy of the suite (mirrored tree, repo untouched) and the marker is:

```
T12DBG no-mission-file
```

So with a missing/unreadable diff file, `leadv2-review-run.sh` writes **no
`review-mission-sonnet.md` at all**. The stderr half of M1 works —
`leadv2-review-run.sh:600` does print `diff file missing or unreadable: <path>`, and its call site at
`:1183` does not swallow stderr. What is missing is the safe fallback the case actually asserts: an
unreadable diff must degrade to **EXHAUSTIVE ROUND 1**, which the file's own header calls "always
safe", and must not write the round sidecar.

That matters beyond the test. Today a review whose diff file went missing produces no mission,
silently reviews nothing, and the lane reads as "review ran". That is the lying-green shape this
whole wave exists to remove.

## Your task

Make a missing or unreadable diff file degrade to an exhaustive round-1 mission instead of producing
nothing:

1. The mission file must be written, and must carry `EXHAUSTIVE ROUND 1`.
2. `.review-round.state` must **not** be written — an unreadable diff is not evidence of a round.
3. The stderr line stays; do not remove or reword it, T12 greps for `diff file missing`.
4. Do not widen this into "any failure degrades to exhaustive". The scope is the `ok=0` path from
   `_review_diff_hash`, nothing else.

## Prove it

- `test-review-round-exhaustive.sh` at **24/0**, and `test-review-roundcap` and
  `test-codex-dead-reroute` still green — all three, **ten consecutive runs each**, every count line
  pasted. Ten, not five.
- **A negative control per changed function body**, through
  `plugins/leadv2/scripts/leadv2-mutation-control.sh`, mutation **inside the body**, never at top
  level. One is mandatory: revert the fallback so the missing-diff path writes no mission, and show
  T12 goes red with the literal red line. `baseline_rc=0` / `mutated_rc=1`, tool exit 0.
- A mutant that reddens a suite by **crashing** it is not a control — that happened on another lane
  tonight (`JSONDecodeError`), it reads exactly like a pass, and it was discarded and redone. A
  stack trace instead of a failed assertion means the anchor is wrong.

## The branch is polluted — this is part of the task

`0182ced5` swept **18 files of shared-tree churn** into the branch: `docs/leadv2/active.yaml` and its
lock, `.bus.lock`, `.merge.lock`, `bus.jsonl`, `merge-queue.jsonl`, `open-threads.md`, `questions`,
two other lanes' `journal.md`, three other dispatches' `phases.d/*.yaml`, and `docs/LEAD_V2_STATE.md`.
Only two files are this lane's work.

Land your work so that the final branch changes **only** `leadv2-review-run.sh`,
`test-review-round-exhaustive.sh`, `test-codex-dead-reroute.sh` and this handoff directory. Carrying
a frozen `active.yaml` onto main is the registry-fragmentation defect another session is actively
fixing, and the lock and journal files belong to lanes that are running right now.

Do this additively — a fresh commit on the branch that restores those paths to main's content, or a
clean re-application of the two real diffs. **Never** `reset --hard`, `clean`, `stash`, or
`worktree prune`: the tree is shared and live lanes stand next to yours.

## Constraints

- Do not touch `tests/run-all.sh`, `tests/known-red-suites.txt`, `main`, or `docs/leadv2/`.
- No assertion is weakened; nothing is added to the known-red list.
- Do not merge to main. Leave the branch green with a report.

## Report

The thirty count lines (three suites × ten runs), each control's `baseline_rc`/`mutated_rc` pair with
its red line, the final `git diff --name-only main...HEAD`, and the commit shas. Nothing else.
