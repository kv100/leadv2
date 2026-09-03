# WORKER-DOD-GATE-01 — a worker may not exit "complete" until a mechanical definition-of-done gate passes

LANE_WRITES: plugins/leadv2/scripts/leadv2-worker-epilogue.sh,plugins/leadv2/scripts/lib/leadv2-dod-gate.sh,plugins/leadv2/scripts/leadv2-mutation-control.sh,plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/prompts/**,plugins/leadv2/scripts/tests/test-worker-dod-gate.sh,tests/run-all.sh,docs/handoff/WORKER-DOD-GATE-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST. Never commit `docs/leadv2/`,
`docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`. Commit by LANE_WRITES pathspecs; an uncommitted exit
is a failed round. Review-facing text in ENGLISH.

## Why (founder, 2026-09-02: "как сделать так чтобы не было столько раундов?")
Tonight's 12 reviews across 9 lanes produced 1–3 Highs each; a round costs 30–45 min. The lead sorted
every High by cause. Only 2 of 19 were design disagreements. The rest were mechanical and would have
been caught by a script BEFORE the model review:
| cause | count | example |
|---|---|---|
| brief step skipped (no report.md, a "paste X" with nothing pasted, a suite not registered) | 5 | GUARD-CENSUS R1, WORKER-MCP R1, MERGE-QUEUE R1 |
| mutation control that never applied its mutant (prints "red-capable" while the suite stays green) | 4 | CACHE-TRUTH R2, BRAIN-CLASS R1, WORKER-MCP R1, FABLE R2 |
| runtime/state files in the diff (docs/leadv2 symlinks, LEAD_V2_STATE.md, phases.d) | 3 | FABLE R3 (Critical), CACHE-TRUTH R2 |
| untagged external claim (no evidence:, no UNVERIFIED) | 3 | HOOK-CACHE R1/R2, FABLE R3 |
| reviewer hallucination (finding cites text that does not exist) | 2 | PROMISE R4, MERGE-QUEUE R2 |
Each of the first four rows is a checkable predicate. Today nothing checks them until a reviewer model
spends a round on it.

## Do
1. `lib/leadv2-dod-gate.sh` — a pure-bash gate the epilogue runs BEFORE the worker is allowed to exit
   `complete` (and that `leadv2-review-run.sh` runs BEFORE spending a model). Checks, each with a named
   reason line `dod_fail check=<name> …`:
   a. `report.md` exists under the task's handoff dir, is committed, and contains the round heading the
      brief asked for ("## Round N evidence" or "## Evidence").
   b. Every brief line containing "paste" / "RUN and paste" has a corresponding fenced block in
      report.md under a heading that names it (match by the suite/control name in the line).
   c. Every `tests/*.sh` / `scripts/tests/*.sh` the diff adds is registered in `tests/run-all.sh`
      (stem or EXTRA_SUITE_MAP) — verify with `tests/run-all.sh --scope changed --dry-run` output.
   d. The committed diff (`git diff main HEAD`) contains no path from the runtime-state list
      (docs/leadv2/**, docs/LEAD_V2_STATE.md, docs/handoff/dispatch-nw*, plus whatever
      `lib/leadv2-land.sh` lists once LAND-PATH-IS-BROKEN-01 lands — read it if present).
   e. Every sentence in report.md matching an external-claim shape (`docs say`, `macOS`, `Claude Code`,
      `Z.AI`, `endpoint`, `rate limit`, `version`) carries `evidence:` or `UNVERIFIED` within 2 lines.
2. `leadv2-mutation-control.sh <suite> <file> <sed-or-patch>`: applies the mutation in a scratch copy
   of the lane (never the lane itself), runs the suite, REQUIRES a non-zero exit and prints the failing
   assertion; then discards the copy. Exit non-zero with `control_not_applied` when the anchor does not
   match exactly once. Briefs and the worker preamble tell workers to use it instead of hand-editing;
   the gate (1b) accepts a mutation control only when the pasted block was produced by this script (it
   prints a `MUTATION-CONTROL ok suite=… mutant=… red_line=…` line to match).
3. Epilogue: on `dod_fail`, do not exit — feed the reason lines back to the worker as the next turn
   ("DoD gate failed: … fix and re-run") up to 2 times, then exit `complete_with_dod_fail` so the
   dispatcher journals it and the lead sees it before any review. Review engine: on `dod_fail`, status
   `blocked reason=dod:<check>` with zero model spend.
4. Suite `test-worker-dod-gate.sh`: one fixture per check (a–e) red and green, plus the mutation
   runner: a fixture suite + a mutation that applies → ok line; a mutation whose anchor is absent →
   `control_not_applied`. Mutation negative controls, RUN via the new runner and paste: remove check (d)
   → its fixture red; remove the anchor-count guard → the second runner case red. Revert. Register in
   `tests/run-all.sh`; paste `--scope changed` + FALSIFIABLE.
5. `report.md`: the gate's output on THIS lane (it must pass its own gate), the table above with the
   check that would have caught each row, and what the gate does NOT catch (design disagreement,
   reviewer hallucination — those go to GATE-PROVES-ITS-OWN-CONTROL-01).

## Do NOT
- Do not weaken the review: the gate is in ADDITION to the model review, never a replacement.
- Do not add a model call to the gate — it is bash + grep + git only, under 5 s.
