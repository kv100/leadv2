# BRAIN-CLASS-LIVE-01 — fix-round 4

**Class:** Standard fix-round. **Lane:** worktree-BRAIN-CLASS-LIVE-01 (resume; merge `main` FIRST).

## Why this round exists
R3 review (glm arm; sentinels came back in Russian, lead adjudicated by hand from
`docs/handoff/BRAIN-CLASS-LIVE-01/review-glm.md`): `FAIL high=2`.

1. `plugins/leadv2/scripts/tests/test-brain-class-live.sh:214` — case (d) re-entry asserts `*"Heavy"*`
   against the COMBINED stdout+stderr, so the assertion survives when the class is only echoed in a
   log/diagnostic line and the actual routed class is wrong. Assert on the one line that carries the
   decision (the routed-class line on its own stream), not on a substring anywhere in the merged output.
2. `tests/run-all.sh:133` — the suite is admitted flaky: cases (a)/(b) fail ~1 in 3 (stated in the
   report, reproduced by the reviewer). A flaky suite is not evidence; find the nondeterminism (shared
   tmp path, ordering, time-based wait, leftover lane state) and remove it. Prove with 10 consecutive
   green runs pasted in the report.

## Do
1. `## R4 findings` rows in report.md: REAL/REFUTED + evidence command. No command = REAL.
2. Fix 1: assertion on the decision line; add a negative control that makes the route return a wrong
   class while still logging "Heavy" elsewhere → suite must go red (show it).
3. Fix 2: root-cause the flake; paste `for i in $(seq 10); do bash …; done` tails — 10/10 green.
4. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`.
- Reviewer contract reminder for the NEXT review of this lane: English sentinels only.
- Commit on the lane, tree clean, `main` merged.

## Done when
- both findings REAL→fixed with evidence; 10/10 green; FALSIFIABLE.
