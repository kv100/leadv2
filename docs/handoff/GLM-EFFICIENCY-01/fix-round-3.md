# GLM-EFFICIENCY-01 — fix-round 3 (Sonnet arm: GLM failed the class-map wiring twice)

**Class:** Standard fix-round, **arm: Sonnet**. **Lane:** worktree-GLM-EFFICIENCY-01 (resume; merge `main` FIRST).

## Why this round exists
R2 review (opus, committed-tree diff c918a2d9): `FAIL critical=1 high=2`. Full rows:
`docs/handoff/GLM-EFFICIENCY-01/review-findings.json`.

1. **Critical** `leadv2-dispatch-code.sh:5119` — `_glm_effort_for_class` matches LOWERCASE classes,
   but `DC_TASK_CLASS` is always Title-case (Light/Standard/Heavy/Strategic). Every arm is dead; every
   dispatch falls to the `RESOLVED_EFFORT` fallback while journaling `source=class_map` — a lying label.
2. **High** `tests/test-glm-effort-wiring.sh:683` — the two "end-to-end" dispatch assertions go green
   THROUGH the `*)` fallback, not the class map; the suite stays green with the whole case body deleted;
   the negative-control mutant cannot detect it.
3. **High** `tests/test-glm-effort-wiring.sh:554` — `_effort_run_v1 ""` never unsets `GLM_EFFORT`, so the
   "unset → no flag" assertion goes red whenever the suite runs inside a GLM lane (exactly where
   EXTRA_SUITE_MAP schedules it and where the dispatcher exports GLM_EFFORT).

## Do
1. `## R3 findings` table in report.md: REAL/REFUTED + evidence command per row. No command = REAL.
2. Fix 1: normalise the class once (`tr '[:upper:]' '[:lower:]'` or match Title-case) at the ONE entry
   point; journal `source=class_map` only when a map arm actually matched, `source=fallback` otherwise.
3. Fix 2: the e2e assertions must prove the MAP fired — assert the journaled `source=class_map` AND the
   mapped effort value for Light/Standard/Heavy (three distinct values), plus one case that proves the
   fallback path journals `source=fallback`. Negative control: delete the map body in a mktemp copy → red.
4. Fix 3: `_effort_run_v1 ""` must `env -u GLM_EFFORT` (or `unset` in a subshell); run the suite once with
   `GLM_EFFORT=high` exported and once without — paste both tails green.
5. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; `tests/run-all.sh --scope changed`; paste both.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`,
  `scripts/dispatch-nc-mutant.*` (mutants live in mktemp).
- Commit on the lane, tree clean, `main` merged.

## Done when
- 3 findings REAL→fixed with runtime evidence (journal lines, not greps); FALSIFIABLE; run-all tail green.
