# BRAIN-CLASS-LIVE-01 — fix-round 3 (one High, mechanical)

**Class:** Light fix-round. **Lane:** worktree-BRAIN-CLASS-LIVE-01 (resume; merge `main` FIRST).

## The finding (opus R2 review, committed-tree diff f19d16d9)
`plugins/leadv2/scripts/tests/test-brain-class-live.sh:202` — case (d) re-entry is the ONE dispatch
invocation in the suite that does not blank `CLAUDE_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR` /
`LEADV2_PROJECT_ROOT`, so the suite goes deterministically RED whenever `CLAUDE_PROJECT_DIR` is exported
(reviewer reproduced 3/3). Every other case blanks them.

## Do
1. Verify on the lane tip: run the suite once with `CLAUDE_PROJECT_DIR=/tmp/x` exported and paste the
   red line into `report.md` §`## R3 findings` (REAL + evidence). Then fix case (d) to use the same
   env-blanking helper as the other cases — no per-case copy-paste; if there is no helper, add one and
   route every case through it.
2. Re-run the suite twice: once with `CLAUDE_PROJECT_DIR` exported, once without; paste both tails.
3. Run `leadv2-suite-falsifiable.sh` on the suite from the LANE ROOT as cwd; paste the verdict.

## Constraints
- Only the suite (and a helper inside it) + `report.md`. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`,
  `phases.d/`, `plugins/leadv2/scripts/docs/`. Commit on the lane, tree clean, `main` merged.

## Done when
- suite green with and without `CLAUDE_PROJECT_DIR` exported; FALSIFIABLE; both outputs pasted.
