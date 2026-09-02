# FABLE-THINK-TIER-01 — fix-round 8 (judge verdict after round cap 2)

**Class:** Standard fix-round. **Lane:** worktree-FABLE-THINK-TIER-01 (resume; merge `main` FIRST).
**Do the work yourself in this lane: no nested agents, no background waits, commit after every step.**

## Why this round exists
An Opus judge re-ran R7 with runtime probes: `VERDICT: FIX-ROUND`, 2 of 4 items resolved.
Full text with the probe outputs: `docs/handoff/FABLE-THINK-TIER-01/judge-r7.md` — read it first.

RESOLVED and mutation-proven, do not touch: item 2 (carrier map, `test-run-all-carrier-map.sh` 5/0, NC
4/1) and item 3 (PyYAML-less fail-closed, NC turns both cases red on a full copy whose baseline is 45/0).

Still open:

1. **The kill switch is STILL dead on the JS channel.** The judge ran the brief's own probe: router says
   `opus`, the child prints `CHILD THINK_MODEL=fable`. Worse, the dispatch-side negative control is
   **vacuous**: re-inserting the skip-if-pinned guard spelled `if [ -z ... ]` (single bracket) instead of
   `if [[ -z ... ]]` leaves the suite at `PASS=45 FAIL=0` while the child-side print shows `CHILD=fable`.
   Runtime case 1e anchors INSIDE the guard, so only a single-spelling grep defends it.
   Required: make the yaml `unavailable: true` win on the JS channel for real (child-side print must say
   `opus`), and make the negative control spelling-independent — it must fail on ANY reintroduction of the
   skip, not just the exact `[[ -z ... ]]` text. Assert on the CHILD's resolved model, never on source text.
2. **`report.md` was never updated in R7** (mtime 06:07 against a 13:12 commit; `grep -c '## R7 findings'`
   = 0). Write `## R7 findings` and `## R8 findings` with REAL/REFUTED + the evidence command per item,
   and paste the `tests/run-all.sh --scope changed` tail.
   NOTE, this bit you before: the judge's own `--scope changed` hit `exit=124` because
   `run-core-offline.sh` burns 600s waiting on a stale lock whose holder pid is dead. If you hit that,
   clear the stale lock dir under `/tmp/leadv2-core-offline-*` (verify the holder pid is dead first with
   `kill -0`), say so in the report, and re-run. Do not paste a timeout as if it were a pass.

## Do — one commit each
1. Fix 1 with a child-side runtime probe pasted (router verdict + `CHILD THINK_MODEL=`), plus the
   spelling-independent negative control shown red in a mktemp FULL copy whose baseline is green.
2. Fix 2: the two report sections + the run-all tail.
3. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
  `plugins/leadv2/scripts/docs/`, `critic.*`. Mutants in mktemp only. Tree clean, `main` merged.

## Done when
- the child prints `opus` under a settings pin + yaml `unavailable: true`; the NC is spelling-independent
  and red; report carries both sections and a real run-all tail; FALSIFIABLE.
