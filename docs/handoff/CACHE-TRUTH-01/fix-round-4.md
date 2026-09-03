# CACHE-TRUTH-01 — fix-round 4

**Class:** Standard fix-round. **Lane:** worktree-CACHE-TRUTH-01 (resume; merge `main` FIRST).

## Why this round exists
R3 review (opus, committed-tree diff a8ca06c2): `verdict=FAIL high=2`. Full text in
`docs/handoff/CACHE-TRUTH-01/.review-findings-dedup.tsv`.

1. `plugins/leadv2/scripts/leadv2-cache-truth.sh:182` — on a mixed stream the `input_tokens` column
   sums only REPORTED turns (unreported turns' input silently vanishes), while the `n_reported==0`
   branch sums ALL turns. One column, two definitions; the reviewer's probe shows 500,100 real input
   printed as a smaller number.
2. `tests/run-all.sh:237` — the deliverable claims 5 EXTRA_SUITE_MAP rows added and "verified", but only
   1 exists: `glm-coder.sh`, `freepool-coder.sh`, `kimi-coder.sh`, `claude-subsession.sh` do not map to
   `test-cache-truth.sh`, so `--scope changed` will not select the suite for those files.

## Do
1. Verify both on the lane tip; row per finding in `report.md` §`## R4 findings`: REAL/REFUTED + evidence
   (grep/probe output). A refute without a command is a REAL.
2. Finding 1: one definition for the column. Either sum ALL turns always and add a separate
   `input_reported` column, or name the column `input_reported` — pick one, document it in the header
   line the script prints, and add a suite case with a mixed stream (reported + unreported turns) whose
   expected number is computed by hand in the test.
3. Finding 2: add the 4 missing `EXTRA_SUITE_MAP` rows; prove selection with
   `bash tests/run-all.sh --scope changed --dry-run` (or the equivalent listing) for a touched
   `glm-coder.sh` — paste the output showing `test-cache-truth.sh` selected. Do NOT write "verified"
   without the pasted output.
4. Run the suite + `leadv2-suite-falsifiable.sh` on it from the LANE ROOT as cwd; paste verdicts.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, or anything under
  `plugins/leadv2/scripts/docs/` (suite pollution). Commit on the lane, tree clean, `main` merged.

## Done when
- both findings REAL→fixed with evidence, or REFUTED with a command; suite green + FALSIFIABLE;
  the 4 map rows present and the selection output pasted.
