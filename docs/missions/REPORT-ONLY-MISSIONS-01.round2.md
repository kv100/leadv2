# MISSION — REPORT-ONLY-MISSIONS-01, round 2 (your change broke the core suite; finish the job)

Your work is in `.claude/worktrees/c5daf449` — `leadv2-dispatch-code.sh` and
`leadv2-dispatch-product-close.sh` are modified. The original mission is
`docs/missions/REPORT-ONLY-MISSIONS-01.md`; re-read it, nothing about it has changed.

**The e2e gate failed on `plugins/leadv2/scripts/tests/run-core-offline.sh`.** That suite passes
clean on `main` (verified by the lead: 43/43, 20/20, 5/5), so the regression is yours. Run it,
read the failure, and fix it — do not weaken or skip the assertion to make it green.

Then finish the mission itself. The deliverable is still: a report-only lane must be gated on its
declared deliverable file, not on a diff, and **`no_work` must stop being a possible verdict for a
lane that declared one**. Today `no_work` cannot distinguish "the analysis is finished" from "the
worker died" — that ambiguity cost three dispatches and zero output on `d44ddd50`.

## Hard constraints
- Do not weaken the diff gate for code lanes.
- Plugin repo only.

## Evidence required
`run-core-offline.sh` green, plus the two fixture runs the original mission asks for (a
report-only lane that wrote its deliverable passes; one that did not fails, naming the missing
path). Report to `docs/missions/REPORT-ONLY-MISSIONS-01.report.md`. End with DELIVERABLE_COMPLETE.
