---
verdict: APPROVE
next_action: continue
lane: worktree-LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01
head: a7f7131c
---

# Lead verification — LANE-OUTCOME round 2

Run by the lead, not read from the worker's report. The lane itself died at the
review gate (`dod_paste_evidence_missing`); the work under it is green.

## 1. The truncation is gone

Ten consecutive runs, `LEADV2_STATE_ROOT` pinned to a scratch dir under `/private/tmp`:
all ten `rc=0`, all ten `test-lane-outcome-reads-state: 7 passed, 0 failed`.
The count line now prints in every outcome. Landed in `ec5eb1ff`.

## 2. The controls bite, and the brief's own prediction was low

Mutation of line 240 (`*) NEXT="respawn"`), read back before trusting the run:

    FAIL: case_verdict_outranks_bound            -- next=respawn, expected none
    FAIL: case_undetermined_work_is_unknown_...  -- next=respawn, expected none
    FAIL: case_unknown_work_never_auto_respawns  -- next=respawn for an undetermined lane
    red count: 3      (baseline_rc=0, mutated_rc=1)

Before the fix the same mutation printed **one** red and stopped. The brief predicted
two; the truth is three. `case_unknown_work_never_auto_respawns` — the case I wrongly
reported as undefended in round 1 — bites, and it could not have been seen before.

Second control, `OUTCOME="unknown"` -> `"died-clean"`: 2 reds, both named.

**This widens the exception to "exactly one red", and I am saying so rather than
smuggling it.** Line 240 is a single product line, but three fixtures reach it
independently, each asserting `next != respawn` from a different state. That is the
same reasoning as one product line serving two call sites — one rung wider.

## 3. Control plane: clean, and the pin is still unproven

`git status --porcelain -- docs/leadv2` before the ten runs: 10 paths. After: the same
10, `comm -13` empty — **my runs added nothing**. The ten are other sessions' live
lanes (`dispatch-567ba028`, `dispatch-59ae8b51`, bus/lock/merge-queue), mtimes ~16 min
before my first run.

The positive control still answers 0: nothing landed in the pinned scratch state root.
So the claim remains **"clean with the pin", never "clean because of the pin"** — the
suite may simply never write to the store. Proving the pin needs a suite known to write.

## 4. Not done

- `plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh.fixed` is untracked
  worker scratch, left in place. It must not be committed.
- The `tests/test-lane-outcome.sh` `case_6` collision (it asserts the old defect,
  undetermined -> `died-clean`) is still a decision, not a footnote.
