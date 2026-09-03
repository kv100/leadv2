# DISPATCH-PIN-CLUSTER-01 — fix round 1 (Heavy; resume, same lane)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PIN-CLUSTER-01`
Your previous round is committed there (2 commits, 11 files, 223 insertions). Read
`docs/handoff/DISPATCH-PIN-CLUSTER-01/context.yaml` — still BINDING, `off_limits[]` unchanged.
This is a resume: **keep the production code you already wrote**; the defect is in the tests.

## What is wrong

Three of the four "negative controls" are grep-for-a-string assertions. They do not execute the
production path at all:

```
tests/test-dirty-lane-never-lands.sh
  grep -q 'terminal="pass_unlanded"' scripts/leadv2-dispatch-ledger.sh
  grep -q 'dirty_lane_retry_exhausted'  scripts/leadv2-dispatch-ledger.sh

tests/test-plan-in-lane.sh
  grep -A20 '^_deliver_plan_into_lane()' … | grep -q 'exit 5'
  grep -A20 '^_deliver_plan_into_lane()' … | grep -q 'cp -f'
```

This is precisely the lying-green disease this repo's own doctrine names: a suite that asserts
**assertion strings exist**. It goes red for the one mutation that deletes the literal, and green
for any refactor that keeps the literal while breaking the behaviour. It proves nothing about
whether a dirty lane can land or whether a missing plan refuses.

`tests/test-class-floor-survives-resume.sh` is the counter-example and the standard to copy: it
sources the real lib and calls `leadv2_admission_write_receipt` /
`leadv2_admission_read_task_receipt` / `_lv2_class_rank`. Do that everywhere.

## Required

Rewrite these three so each keeps the production function under claim REAL and fakes only one
level lower:

1. **`test-dirty-lane-never-lands.sh`** — build a real temp git repo with a real worktree, leave
   one tracked file modified, `source` the ledger and CALL `dispatch_ledger_write_terminal … landed`,
   then assert the row actually written reads `pass_unlanded` and the reason carries `dirty_lane:`.
   Second case: a CLEAN lane must still write `landed` (a guard that refuses everything is not a
   guard). Third case: after N downgrades on one sig8 the terminal must become final `refused`, not
   retryable — that is the D2-LOOP-BOUND requirement and it is currently untested.
2. **`test-plan-in-lane.sh`** — real temp lane, `context.yaml` present in the fake PROJECT_ROOT and
   absent from the lane; CALL `_deliver_plan_into_lane` and assert the file now resolves under
   WORK_ROOT. Then the refusal case: make the copy impossible and assert rc=5 AND
   `lane_plan_missing` was journaled. Assert the no-op case too: `WORK_ROOT == PROJECT_ROOT` copies
   nothing.
3. **`test-lane-containment.sh`** — real temp PROJECT_ROOT + lane worktree. Write a file into the
   MAIN checkout after the baseline is taken and assert `lv2_lane_containment_violation` returns the
   violation. Then the false-positive case, which matters more: writes to the EXCLUDE set must NOT
   trigger it.

## Live evidence you must encode in the exclude-set

When your own round finished, the lane had 18 dirty files and **every one of them was control-plane
residue**, not source: `docs/leadv2/active.yaml`(+`.lock`), `bus.jsonl`, `.bus-offsets`, `.bus.lock`,
`.merge.lock`, `merge-queue.jsonl`, `questions`, `open-threads.md`, `docs/LEAD_V2_STATE.md`,
`docs/leadv2/tasks/*/journal.md`, `docs/handoff/dispatch-*/phases.d/*.yaml`.

That is the D1-EXCLUDES set observed live, and it is also the D2 trap: if `lv2_lane_dirty` counts
these, EVERY lane is dirty and NOTHING ever lands — the fix becomes a total outage. Your exclude
regex must cover all of the above, and `test-dirty-lane-never-lands.sh` must have a case proving a
lane dirty ONLY with control-plane residue still lands.

## Then run the mutations, for real

For each of the four: name the mutation in the suite header, apply it INSIDE the function body in a
scratch worktree, show the suite RED, revert, show it GREEN. Paste the runs. A grep-based suite
cannot satisfy this.

Also add the `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.

## Done means

`git -C <lane root> status --porcelain` shows ONLY the control-plane residue listed above — every
source and test change committed. Report the commit shas and the four red/green mutation runs.
