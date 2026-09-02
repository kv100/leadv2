# WORKER-DOD-GATE-01 — build round 3 (continue; round 2 ended its turns "waiting for a monitor")

**Class:** Heavy (plan approved; `docs/handoff/WORKER-DOD-GATE-01/context.yaml` binding).
**Lane:** worktree-WORKER-DOD-GATE-01 (resume; merge `main` FIRST).

## State you inherit
- `9522b8d4` wip build-attempt-1 (gate lib, mutation-control, wiring diffs).
- `fd6bdbec` step 2: `test-worker-dod-gate.sh` suite + fix check (c). Steps 1 and 2 of
  `build-round-2.md` are DONE; steps 3–6 are NOT (run-all proof, wiring proof, falsifiable verdict, report.md).

## Why round 2 died
The worker backgrounded `tests/run-all.sh --scope changed` under a Monitor and ended its turn four
times with "waiting for the notification". A dispatched worker has no next turn: **a turn that ends on
a wait ends the job.** Rules for THIS worker:
- **Never background a command you need the result of.** Run `tests/run-all.sh --scope changed` in
  the FOREGROUND with `timeout 900`; if it exceeds that, run only the changed suites directly and say so.
- No Monitors, no nested agents, no `isolation:"worktree"`.
- **Commit after every step.** ≤10 turns per step.

## Do — one commit each
3. `tests/run-all.sh` EXTRA_SUITE_MAP rows for every touched carrier; paste the `--scope changed`
   selection output (foreground, timeout 900).
4. Wiring proof: a review-run dry-run on a lane that violates one DoD item writes `review-gate.md`
   with `status: fail reason: dod_<check>` BEFORE any reviewer arm is resolved (no `pool_ok`/`arms=`
   line). Paste the gate file. Include the "mutant copy must be a FULL copy incl. lib/" check if the
   plan's check list has it; if not, add it — it recurred a third time today (BRAIN-CLASS-LIVE-01 R4).
5. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd — paste the verdict.
6. `report.md`: `## What was built`, `## Checks and their negative controls` (table),
   `## Wiring proof`, `## run-all --scope changed`, `## Falsifiability`, `## Not done` (honest).

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
  `plugins/leadv2/scripts/docs/`, `critic.*`. Mutants/fixtures in mktemp only.
- Do not touch REVIEW-SENTINELS-LANGUAGE-01 / LAND-PATH-IS-BROKEN-01 write sets. Tree clean, `main` merged.

## Done when
- steps 3–6 committed with pasted runtime output; FALSIFIABLE; gate refuses a bad lane before pool resolve.
