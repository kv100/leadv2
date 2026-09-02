# FABLE-THINK-TIER-01 — fix-round 6 (design pinned; Sonnet arm — GLM failed the same finding twice)

**Class:** Standard fix-round, **arm: Sonnet** (GLM-failed-twice rule). **Lane:** worktree-FABLE-THINK-TIER-01
(resume; merge `main` FIRST).

## Why this round exists
R5 review (fable, committed-tree diff 94da7bcd): `verdict=FAIL high=4`. Two of them are the SAME
defect the task has carried since R1: the documented kill switch (`model-capability.yaml`
`unavailable: true`) is unreachable. Full text: `docs/handoff/FABLE-THINK-TIER-01/.review-findings-dedup.tsv`.

1. `leadv2-dispatch-code.sh:474` — `LEADV2_THINK_MODEL` export uses `${SCRIPT_DIR}` 20 lines before
   `SCRIPT_DIR` is assigned (:494) under `set -u`; the substitution dies, the var is never exported —
   the R5 kill-switch channel to spawned sessions is dead code. Test 4e is text-grep, so it passed.
2. `leadv2-repo-install.sh:312` — writing `LEADV2_THINK_MODEL=<install-time answer>` into settings.json
   env makes `think_model()` short-circuit on env in every installed repo, so the yaml kill switch is
   dead for ALL bash call sites.
3. `tests/run-all.sh:182` — 6 new carrier rows (`leadv2-glm-policy-resolve.py`, `model-capability.yaml`,
   `leadv2-diverge.js`, `leadv2-learn.js`, `leadv2-diagnose.js`, `leadv2-po-feedback-loop.js`) can never
   fire: the changed-file loop `continue`s on anything that is not a `.sh`.
4. `report.md:150` — the R5 brief required a `## R5 findings` REAL/REFUTED table, the falsifiable-gate
   verdict and the run-all tail; the committed report ends at Round 4 ("Mutation negative controls:
   NOT run — unverified"). The R5 worker did not do the reporting it was asked for.

## Design decision (lead, binding — do not re-litigate)
**The yaml kill switch wins; env is only a default.** Resolution order in `think_model()` and in every
JS/py resolver: (1) `model-capability.yaml` `unavailable: true` for the candidate → skip it, always;
(2) `LEADV2_THINK_MODEL` env, if set and not unavailable; (3) the per-repo main-model file; (4) built-in
default. `leadv2-repo-install.sh` may still write the env default. The export in dispatch-code must
happen AFTER `SCRIPT_DIR` is assigned — move it, do not re-order `SCRIPT_DIR`.

## Do
1. `## R6 findings` table in report.md: one row per finding, REAL/REFUTED + the evidence command. A
   refute without a command counts as REAL.
2. Fix 1–3. For 1: a suite case that RUNS the export path (`bash -c` with `set -u`) and asserts the var
   is present in a spawned child's env — not a grep. For 2: a suite case with `LEADV2_THINK_MODEL=fable`
   exported AND yaml `fable: unavailable: true` → resolver must NOT return fable. For 3: a case that
   touches `model-capability.yaml` alone and shows `--scope changed` selects the suite (paste output).
3. Negative controls: apply each of the three defects again in a scratch copy (temp dir, never the
   canonical tree) and show the suite goes red; then `leadv2-suite-falsifiable.sh` from the LANE ROOT
   as cwd; paste verdicts. Then `tests/run-all.sh --scope changed`, paste the tail.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`.
- Commit on the lane, tree clean, `main` merged.

## Done when
- 4 findings each REAL→fixed with a runtime test or REFUTED with a command; kill switch proven by the
  env+yaml case; carrier rows proven by selection output; FALSIFIABLE; run-all tail green.
