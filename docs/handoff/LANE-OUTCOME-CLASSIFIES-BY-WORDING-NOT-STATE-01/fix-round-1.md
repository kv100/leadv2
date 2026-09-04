# LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01 — round 2: the suite halts at the first failure, so "exactly one red" proves nothing

LANE_WRITES: plugins/leadv2/scripts/tests/test-lane-outcome-reads-state.sh, docs/handoff/LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01/

Work on branch `worktree-LANE-OUTCOME-CLASSIFIES-BY-WORDING-NOT-STATE-01`.
**Do not change `leadv2-lane-outcome.sh`** — round 1's product changes are correct and verified.

## What round 1 got right — keep all of it

Verified by the lead by running it, not from the report:

- suite `test-lane-outcome-reads-state.sh`: **7 passed, 0 failed, ten consecutive runs**, `rc=0`, with
  `LEADV2_STATE_ROOT` pinned to scratch and **zero** dirty paths under `docs/leadv2` before or after;
- the two live behaviours are real and defended: undetermined → `unknown` (not `died-clean`), and
  `unknown` never auto-respawns (`*) NEXT="none"`, line 240);
- the §1 answer is **correct and none of my five candidates**. Verified independently in
  `docs/leadv2/tasks/dispatch-cf509abb/journal.md`: `arm_quota_failed` at 22:14:10 →
  `review_gate … action=arm_advanced` at 22:14:14 → `dispatch_terminal terminal=dead cause=e2e_regression`
  at 22:59:21. The resume never gets its chance when arm-quota exhaustion intervenes first;
- the HONESTY NOTE at `leadv2-lane-outcome.sh:163` is exactly the right call and **my brief's premise
  was the wrong half**: no shipped caller writes `${RUN_DIR}/.gate-verdict`, because the classifier
  runs at raw worker exit, before the review/dod machinery, and is never handed the handoff path.
  Confirmed independently — `grep -rl 'gate-verdict' plugins/leadv2/scripts/` returns nothing.
  "verdict-first" is a forward-compatible seam, not a live behaviour change, and saying so in the
  code instead of claiming the fix is the behaviour we want.

## The gap

`set -euo pipefail` (line 14) plus an unguarded classifier call means the suite **stops after the
first failing case**. Measured: under a single-site mutation of line 240 (`*) NEXT="respawn"`), the
whole output is

```
PASS: case_bash_n
FAIL: case_verdict_outranks_bound -- next=respawn, expected none
```

and nothing else. Cases 3–7 never ran.

This breaks the acceptance criterion itself. "Under each mutation exactly ONE assertion may go red,
and it must be the named one" assumes every case gets a chance to speak. On a suite that halts, one
red is **guaranteed by construction** — the earliest affected case — and says nothing about the
others. I nearly reported that `case_unknown_work_never_auto_respawns` fails to defend its own
branch; it was simply never reached. **That retraction is the reason this round exists**: an
acceptance instrument that cannot be wrong is not an instrument.

## Your task

1. Make the suite run **every** case regardless of failures, and print a final
   `N passed, M failed` line in all outcomes. Keep the non-zero exit when `M > 0`.
2. Guard the calls that `set -e` currently kills — the classifier is *expected* to exit non-zero in
   some cases; capture its status instead of letting it abort the run.
3. Re-verify `case_unknown_work_never_auto_respawns` now that it can actually run: under the line-240
   mutation it must go red **together with** `case_verdict_outranks_bound`, and both are legitimate
   — one product line, two cases that each independently assert `next != respawn`.

## Prove it

- Re-run the line-240 mutation and paste the **full** case list under it. The expected result is two
  reds, both named, and five greens — not one red.
- A mutation of the suite's own runner (make `fail()` exit again) must show the truncation returning:
  that is the control for the fix you are making.
- **A mutant that does not bite is a claim about your anchor**, not about the branch — twice today a
  green suite under mutation meant the anchor sat on a site the fixture never reaches.
- **Read the mutated line back** before trusting a run; a mutation can change sha256 and be inert.
- **Ten consecutive runs**, all exit codes, with `LEADV2_STATE_ROOT` pinned to a scratch dir under
  `/private/tmp` — and `git status --porcelain -- docs/leadv2` before and after, which must be
  **empty both times**. Suites in this repo have been writing into the live control plane through
  repo symlinks; do not add to it.

## Bounds

- Do NOT edit `leadv2-lane-outcome.sh`, `lib/leadv2-parked-detect.sh`, `leadv2-dispatch-code.sh`,
  `leadv2-dispatch-product-close.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`, `main`,
  or `docs/leadv2/`.
- The pre-existing `tests/test-lane-outcome.sh` `case_6` asserts the **old defect** (undetermined →
  `died-clean`). It is out of your write set. Do not touch it and do not weaken your own cases to
  agree with it; the lead is handling that collision separately.
- Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Scratch worktrees under
  `/private/tmp`, removed with `git worktree remove`.
- Commit incrementally — the e2e gate parks lanes at 900s.
- If any instruction here rests on a false premise, stop and say so with the measurement.
- Do not merge to main. Leave the branch green with a report.

## Report

The full case list under the line-240 mutation, the runner control's pair, the ten count lines with
the before/after `git status` results, and the commit shas. Nothing else.
