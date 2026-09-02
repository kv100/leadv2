# FABLE-THINK-TIER-01 — fix-round 5

**Class:** Standard fix-round. **Lane:** worktree-FABLE-THINK-TIER-01 (resume; merge `main` FIRST, before any edit).

## Why this round exists
R4 review (opus, diff from the committed tree, hash 3fa2fe7f): `verdict=FAIL critical=1 high=5`.
Findings are on disk in the lane, read them yourself — the lead has NOT triaged them:
- `docs/handoff/FABLE-THINK-TIER-01/review-findings.json`
- `docs/handoff/FABLE-THINK-TIER-01/.review-findings-dedup.tsv` (full text per finding)

Locations flagged: `leadv2-session-route.sh:63` (Critical), `workflows/leadv2-diverge.js:32`,
`tests/test-fable-think-tier.sh:166,170`, `leadv2-ask.sh:514`, `tests/run-all.sh:177`.

## Do — per finding, in this order
1. **Verify before fixing.** Open the cited line on the lane tip. Two earlier rounds of this task were
   spent on reviewer hallucinations (a cited line that did not exist, a claim about a file that was
   dirty from a suite run). For each finding write in `report.md` §`## R5 findings` one row:
   `id | file:line | REAL / REFUTED | evidence (grep -n output or the exact command that shows it)`.
2. **REAL → fix** in the lane, with the negative control for the suite that covers it (a mutation
   inside the function body that turns `test-fable-think-tier.sh` red, shown in the report).
3. **REFUTED → no code change**, but the evidence row is mandatory; a refute with no command is a REAL.
4. Run `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-fable-think-tier.sh`
   and paste the verdict into the report. Run the full `tests/run-all.sh --scope changed` and paste the tail.

## Constraints
- Stay in LANE_WRITES. Do not touch `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/` — suites dirty them;
  leave them out of the commit.
- Commit on the lane (worker epilogue), working tree clean, `main` merged.

## Done when
- every R5 finding has a REAL/REFUTED row with evidence; every REAL is fixed and covered
- falsifiable gate prints FALSIFIABLE; `run-all.sh --scope changed` green on the merged tree
