# GLM-EFFICIENCY-01 — fix-round 2 (review blocked before findings)

**Class:** Standard fix-round. **Lane:** worktree-GLM-EFFICIENCY-01 (resume; merge `main` first).

## Why this round exists
Review-run R1 stopped at the falsifiability gate, before any model review ran:
`review_gate status=blocked reason=suite_falsifiability_undetermined suite=plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh`.
"Undetermined" = the gate could not prove the suite goes RED under its declared negative control
(watchdog 180s, or no parseable negative-control declaration, or the control did not flip the suite).

## Do
1. Read `plugins/leadv2/scripts/leadv2-suite-falsifiable.sh` and satisfy its contract exactly for
   `test-glm-effort-wiring.sh`: a declared negative-control mutation INSIDE the function under claim
   (`_glm_effort_for_class` / the `--effort` pass-through at `leadv2-dispatch-code.sh` ~:5100), applied
   in a scratch copy, that turns the suite red; the suite must finish well under 180s.
2. Run `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh`
   and paste its full output into `docs/handoff/GLM-EFFICIENCY-01/report.md` under `## Falsifiability proof`.
   The verdict line must read FALSIFIABLE. Anything else = not done.
3. Keep R1 scope intact (effort wiring, whitelist low|medium|high|max, capability yaml). Do not touch
   files outside LANE_WRITES.

## Done when
- suite green on the lane tip AND the falsifiable gate prints FALSIFIABLE, both pasted in report.md
- lane committed (worker epilogue) with `main` merged, working tree clean
