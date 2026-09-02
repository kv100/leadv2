# WORKER-MCP-ALL-ARMS-01 — fix-round 4 (Sonnet arm: GLM failed the same shapes twice)

**Class:** Standard fix-round, **arm: Sonnet**. **Lane:** worktree-WORKER-MCP-ALL-ARMS-01 (resume; merge `main` FIRST).

## Why this round exists
R3 review (opus, committed-tree diff d815dba0): `FAIL high=4`. Full rows:
`docs/handoff/WORKER-MCP-ALL-ARMS-01/review-findings.json`.

1. `lib/leadv2-worker-mcp.sh:210` — the "code-intel MCP unavailable" fallback note is INVERTED: every
   branch that emits it describes a spawn that still inherits the full default MCP set, so the note now
   tells the default sonnet arm (the most-used one) to stop using `mcp__*` tools it actually has.
2. `tests/test-worker-mcp-all-arms.sh:1163` — dispatcher injection is asserted by two greps only;
   deleting `mission="${_ci_txt}"…` (dispatch-code.sh:5115) removes the preamble from every spawn and
   the suite stays green. This is the round-1 defect shape recurring.
3. `report.md:253` — §4 claims a completed `run-all.sh --scope changed` run; the evidence block is the
   literal token `RUNALL_PLACEHOLDER`. The changed-scope gate has no artifact.
4. `config/codex-mcp-servers.toml:283` — an evidence-free claim ("`codex exec --help` offers only
   `-c key=value` … neither forwarded by the companion") decides NOT to wire the codex arm; no probe
   output anywhere.

## Do
1. `## R4 findings` table in report.md: REAL/REFUTED + evidence command per row. No command = REAL.
2. Fix 1: emit the note ONLY on a branch whose spawn really lacks the code-intel servers (prove per arm
   with the spawned child's `--mcp-config`/allowed-tools print, not a grep); delete it from the others.
3. Fix 2: the injection test must RUN the dispatcher entry that builds the mission (dry-run / stub
   spawn) and assert the preamble text is present in the mission the child would receive; negative
   control in a mktemp copy with the `mission="${_ci_txt}"` line deleted → red (show it).
4. Fix 3: run `tests/run-all.sh --scope changed` for real; paste the tail in §4, replace the placeholder.
5. Fix 4: paste the actual `codex exec --help` output (the relevant lines) and the companion's forwarded
   argv; if the claim is true, tag the decision `evidence: <cmd>`; if false, wire the codex arm.
6. `leadv2-suite-falsifiable.sh` from the LANE ROOT as cwd; paste the verdict.

## Constraints
- LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `plugins/leadv2/scripts/docs/`.
- Commit on the lane, tree clean, `main` merged.

## Done when
- 4 findings REAL→fixed with runtime evidence; no placeholder tokens anywhere in report.md; FALSIFIABLE.
