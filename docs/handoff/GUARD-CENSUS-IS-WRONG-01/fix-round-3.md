# GUARD-CENSUS-IS-WRONG-01 — fix-round 3

**Class:** Standard fix-round. **Lane:** worktree-GUARD-CENSUS-IS-WRONG-01 (resume; merge `main` FIRST).

## Why this round exists
R2 review (opus, committed-tree diff 0c0dd161): `verdict=FAIL high=2`, both in
`plugins/leadv2/scripts/leadv2-guard-census.sh` and both about the DEFAULT column that feeds the
founder-facing delete list:

1. `:417` — `dflt` is assigned only inside the wired+present branch, so not-wired / missing rows
   print the PREVIOUS guard's default (13 wrong rows in the shipped census artifact).
2. `:419` — the DEFAULT regex accepts only `:-0|1`, so 19 of 93 flag-gated guards print `always`
   (unconditional) when they are actually gated.

Full text: `docs/handoff/GUARD-CENSUS-IS-WRONG-01/.review-findings-dedup.tsv` (also 4 Low — read them,
fix the cheap ones, list the rest as deferred with a reason).

## Do
1. Verify both on the lane tip (`grep -n` output in report.md §`## R3 findings`, REAL/REFUTED + evidence).
2. Fix: reset `dflt` per row before the branch; widen the DEFAULT parser to every gate shape the
   census actually meets (`${X:-0}`, `${X:-1}`, `${X:=..}`, `${X-..}`, quoted forms, `[[ "${X:-0}" == 1 ]]`)
   — enumerate the shapes from the live tree with a grep and put that grep in the report.
3. Re-run the census against the live tree and diff the DEFAULT column before/after: the report must
   state how many rows changed and that zero rows still say `always` for a flag-gated guard.
4. Suite: add a fixture guard for each shape; negative control = re-introduce the stale-`dflt` bug in a
   scratch copy and show the suite goes red. Run `leadv2-suite-falsifiable.sh` on the suite, paste the verdict.

## Constraints
- LANE_WRITES only. Do not commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/` (suite pollution).
- Commit on the lane (worker epilogue), tree clean, `main` merged.

## Done when
- both Highs fixed with evidence; census DEFAULT column re-generated and diffed in the report
- suite green + FALSIFIABLE; `tests/run-all.sh --scope changed` green on the merged tree
