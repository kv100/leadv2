# CONTROL-PLANE-REVIEW-01 / F3 — Judge review

Scope: read-only source review. Seed facts are cited, not re-measured.

## Findings

1. **DEFECT — deploy LLM-judge is advisory, not a load-bearing gate.**
   **Evidence:** `plugins/leadv2/scripts/leadv2-llm-judge.sh:456-458` explicitly stops at producing a prompt for the lead; `:510-517` only prints paths/model and exits 0. Its parser returns a no-go as exit 1 (`plugins/leadv2/scripts/leadv2-llm-judge-parse.sh:231-235`), but the only in-tree deployment consumer found is the human/agent protocol in `plugins/leadv2/skills/leadv2-deploy/SKILL.md:61-79`; its asserted block action is likewise prose at `:89-94`. Production code consumers of `llm-judge.yaml` are status renderers only (`plugins/leadv2/scripts/leadv2-status.sh:166-179`, `:305-317`).
   **Mechanism:** no dispatcher/deploy controller consumes either parser rc or `llm_judge.verdict`; a lead must remember to perform the next instruction.
   **Failure:** a valid `no-go` can be written, then deployment proceeds because no executable gate reads it. This answers the founder question negatively for the deploy verdict.
   **Remedy:** make the deploy transition consume one durable verdict artifact and refuse `no-go`/missing/unreadable states.

2. **DEFECT — known-bad deploy-judge results are normalized into an allowed outcome.**
   **Evidence:** parse failure writes `verdict: go-with-caveats` (`leadv2-llm-judge-parse.sh:108-132`) and the parser exits 3; the prescribed Auto-Gate accepts `go-with-caveats` (`skills/leadv2-deploy/SKILL.md:83-94`). A hard cost ceiling writes `go-with-caveats` plus `skipped: True` (`leadv2-llm-judge.sh:423-452`), and the same protocol accepts *any* skipped result (`skills/leadv2-deploy/SKILL.md:89-94`).
   **Mechanism:** failure/absence is represented as an admissible verdict rather than a distinct non-clean state.
   **Failure:** malformed YAML, an interrupted judge, or quota hard-stop may silently meet the documented Tier-A predicate rather than require a manual decision. This is the false-green disease, even before finding 1's missing reader.
   **Remedy:** preserve a typed `judge_unavailable`/`parse_failed` state and exclude it from silent deployment.

3. **SOUND — task-judge timeout now distinguishes “answered but killed” from “did not answer.”**
   **Evidence:** after the bounded CLI call (`leadv2-task-judge.sh:344-348`), rc 124/137 only becomes `timeout` when `raw` is empty (`:349-367`); non-empty output flows through the envelope parser (`:370-467`) and schema validator (`:614-629`). Failures are durably labelled `judge_path=judge_fail` and a named cause in the journal (`:493-511`, `:631-636`).
   **Mechanism:** timeout status is no longer decisive over a captured body; a complete answer can produce a `judge` estimate, while truncation is accurately `envelope_parse` or `schema_invalid`.
   **Failure prevented:** a completed “complex/safety” estimate at the deadline is no longer discarded and replaced with a cheaper fallback. This confirms the historic timeout finding has been fixed, not merely documented.

4. **SOUND, with a bounded limitation — the dispatch task-judge composes into the arbiter.**
   **Evidence:** dispatcher invokes it before routing (`leadv2-dispatch-code.sh:8744-8749`); its complexity/provenance are put in the arbiter descriptor (`:9481-9511`), and the arbiter invocation is the selection source (`:9511-9532`). On judge failure the task-judge emits an explicit fallback rather than blocking (`leadv2-task-judge.sh:607-636`); the dispatcher labels truly unavailable output and degrades to unknown (`leadv2-dispatch-code.sh:3371-3404`).
   **Mechanism:** this judge changes the descriptor from which the arbiter ranks arms, rather than merely logging beside it.
   **Failure scenario:** the remaining limitation is intentional availability bias: a failed task-judge can reduce a task to unknown/heuristic shaping, so an under-classified task may get a weaker route. The failure is visible, not masqueraded as a clean judge verdict.

5. **MISSING-KNOB / authority split — deploy judge model resolution can still diverge from the arbiter.**
   **Evidence:** `think_model()` now calls `_think_arbiter_decide` absent an env pin (`leadv2-router.sh:466-488`), and that helper builds a constrained descriptor and calls `route_arbiter` (`:409-460`); the prior “fable only, independent of arbiter” claim is therefore superseded. However, deploy judge first takes a bare think result (`leadv2-llm-judge.sh:391-398`) then independently calls legacy phase/step routing and overwrites `model` if it emits output (`:400-419`). The bare call has no `--role judge`, class, or task id (`leadv2-router.sh:492-510`), therefore uses the heavy default (`config/model-capability.yaml:316-325`), while the second route's model is not reconciled with the arbiter result.
   **Mechanism:** two sequential selectors can bind the spawned judge; the latter silently wins when available.
   **Failure:** the judge may run a model that differs from the arbiter’s budget/capability decision, invalidating the claim of one authoritative routing decision. Pass `--role judge --class --task-id` and use that one resolved result.

6. **DEFECT — the advertised Haiku-first judge path is both unconfigured and structurally mismatched.**
   **Evidence:** the main script hardcodes Light/Standard plus executable presence (`leadv2-llm-judge.sh:104-123`) despite claiming registry configuration at `:99-102`. It tests for a packet *before* assembling one (`:107-108`; assembly begins `:126-340`), and the assembled packet is `/tmp/deploy-packet-<id>.yaml` with a `deploy_packet` wrapper (`:290-319`). Haiku instead reads only the handoff packet (`leadv2-llm-judge-haiku.sh:26-32`) and expects unwrapped fields such as `classification`, `premortem_verdict`, and `coverage_pct` (`:41-47`).
   **Mechanism:** on a fresh task Haiku never runs; on a stale/pre-existing packet it judges defaults or a stale shape, then `go`/`no_go` is copied as the final file (`leadv2-llm-judge.sh:112-118`).
   **Failure:** a Standard deploy can be passed or blocked from defaults/stale input rather than the current packet. Use one packet schema and assemble it before selecting the Haiku path.

7. **SOUND — verdict artifacts are durable and status-visible, though not enforcement-visible.**
   **Evidence:** normal parse writes `docs/handoff/<task>/llm-judge.yaml` (`leadv2-llm-judge-parse.sh:53-61`, `:161-180`), and status reads and displays its verdict/risk (`leadv2-status.sh:166-179`, `:305-317`). Task estimates are additionally journalled and, under v2, appended under lock to `route-estimates.jsonl` (`leadv2-task-judge.sh:493-522`).
   **Mechanism:** later sessions can recover what was said; artifact loss is not the primary defect.
   **Failure prevented:** an answer is not inherently lost with the process—provided the lead actually invokes the parser.

## Seed-fact use

S1/S2 are accepted as measured: Fable’s shared-plus-scoped quota and the mixed meaning of `cost` make it especially unsafe for the deploy judge to bypass/reselect around arbiter policy. See `seed-facts.md:7-42`. S3’s single-arm, cheapest-capable output is also accepted as measured; finding 5 identifies that the deploy path currently does not reliably bind that selection. See `seed-facts.md:44-56`.
