# FABLE-THINK-TIER-01 — fix-round 7 (judge verdict after round cap)

**Class:** Standard fix-round. **Lane:** worktree-FABLE-THINK-TIER-01 (resume; merge `main` FIRST).

## Why this round exists
Review round cap was reached; an Opus judge re-ran the R5 findings against R6 (commit 7c5cba26) with
RUNTIME probes. Verdict: FIX-ROUND. Full text with the probe outputs:
`docs/handoff/FABLE-THINK-TIER-01/judge-r6.md` — read it first.

Resolved and mutation-proven: finding 1 (export after SCRIPT_DIR) and finding 3 (carrier rows fire).
Still open:
1. **Kill switch dead on the JS channel** — `leadv2-dispatch-code.sh:495` `-z` guard passes a
   settings.json pin straight through: the child sees `fable` while the router says `opus`. The pinned
   design (yaml `unavailable: true` wins, env is only a default) must hold on EVERY channel the think
   model reaches a spawned session: bash resolver, the exported env for JS workflows, and the JS
   resolvers themselves. Probe: settings pin `fable` + yaml `fable: unavailable: true` → a spawned
   workflow/child must resolve `opus`; paste the child-side print.
2. **New dead map row** at `tests/run-all.sh:282` — remove or make it fire; prove with the selection
   output for a touched carrier.
3. **Kill switch fails OPEN without PyYAML** — the yaml read must fail CLOSED (treat the model as
   unavailable, or fall back to a pure-bash/grep read of `unavailable: true`); add the no-PyYAML case to
   the suite (run with `python3 -c 'import yaml'` shimmed to fail).
4. **Report** — the `tests/run-all.sh --scope changed` tail is still missing from report.md; paste it.

## Do
1. `## R7 findings` rows: REAL/REFUTED + evidence command per item above.
2. Fix 1–3 with a suite case each + a negative control that goes red in a mktemp copy (show it).
3. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; `tests/run-all.sh --scope changed`; paste both.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`.
- Commit on the lane, tree clean, `main` merged.

## Done when
- all 4 items REAL→fixed with runtime evidence (child-side prints, not greps); FALSIFIABLE; run-all tail pasted.
