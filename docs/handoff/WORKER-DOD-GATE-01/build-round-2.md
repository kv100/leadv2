# WORKER-DOD-GATE-01 — build round 2 (continue from committed WIP; worker 1 hit max_turns at 111)

**Class:** Heavy (plan approved at Gate 1; `docs/handoff/WORKER-DOD-GATE-01/context.yaml` is binding).
**Lane:** worktree-WORKER-DOD-GATE-01 (resume; merge `main` FIRST). Codex arm is dead on this machine —
expect sonnet.

## State you inherit (committed on the lane as "wip: build-attempt-1")
- `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` (420 lines, NEW) — the gate library.
- `plugins/leadv2/scripts/leadv2-mutation-control.sh` (193 lines, NEW).
- Wiring diffs in `leadv2-review-run.sh` (+45), `leadv2-dispatch-product-close.sh` (+48),
  `lib/leadv2-worker-epilogue.sh` (+116), `leadv2-lane-outcome.sh`, `leadv2-helpers.sh`, `tests/run-all.sh` (+4).
- NOT done: no suite, no `report.md`, no falsifiability verdict, no `--scope changed` proof, nothing
  run end-to-end. Read the WIP first (`git show --stat HEAD`), do not rewrite what works.

## Budget rule (why round 1 died)
Worker 1 spent 111 turns and committed nothing. **Commit after every completed step** (`git add
<LANE_WRITES>; git commit -m "step N: …"`) so a turn cap never loses work again. ≤10 turns per step.

## Do — in this order, one commit each
1. Smoke the WIP: run the gate library against THIS lane (`bash plugins/leadv2/scripts/lib/leadv2-dod-gate.sh
   --lane . --handoff docs/handoff/WORKER-DOD-GATE-01` or whatever the entry is) — it must produce the
   English-sentinel output the plan pinned (`dod_gate status=<pass|fail> reason=dod_<check>`), and exit
   non-zero on a missing item. Fix whatever does not run. Paste the output in report.md.
2. Suite `plugins/leadv2/scripts/tests/test-dod-gate.sh`: one case per check from context.yaml (dirty
   pollution in diff, missing report sections, unrun negative controls, claimed-but-absent
   EXTRA_SUITE_MAP row, mutant file in canonical tree, non-English sentinels), each with a NEGATIVE
   CONTROL that mutates the check in a mktemp copy and shows red. Fixtures live in mktemp only.
3. `tests/run-all.sh` EXTRA_SUITE_MAP rows for every touched carrier; prove with
   `tests/run-all.sh --scope changed` output pasted.
4. Wiring proof: a review-run dry-run on a lane that violates one DoD item must write
   `review-gate.md` with `status: fail reason: dod_<check>` BEFORE any reviewer arm is resolved
   (no `pool_ok`/`arms=` line). Paste the gate file.
5. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd — paste the verdict.
6. `report.md`: sections `## What was built`, `## Checks and their negative controls` (table),
   `## Wiring proof`, `## run-all --scope changed`, `## Falsifiability`, `## Not done` (honest).

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
  `plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.
- Do not touch REVIEW-SENTINELS-LANGUAGE-01 / LAND-PATH-IS-BROKEN-01 write sets.
- Commit on the lane, tree clean, `main` merged.

## Done when
- steps 1–6 committed, each with pasted runtime output; suite FALSIFIABLE; gate refuses a bad lane before pool resolve.
