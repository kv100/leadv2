# ONE-PATH-PLAN-RUN-01 — build leadv2-plan-run.sh (Plan consolidation)

Goal: implement the Plan half of ONE-PATH-EVERYWHERE-01 — a sole-owner bash engine
`plugins/leadv2/scripts/leadv2-plan-run.sh`, mirroring the shipped review engine
`plugins/leadv2/scripts/leadv2-review-run.sh` (read it first; reuse its arm-pool /
quota-filter / journal patterns, do not fork new conventions).

Authoritative design: `docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md`
(census rebuilt from source; §0 documents the missing-prerequisite gap — trust its
file:line census, treat §7 as open questions, not verdicts).

Scope:
1. `leadv2-plan-run.sh` owns Phase 2 Plan end-to-end: resolves a planner arm pool
   (codex via leadv2-codex-planner.sh as one arm; glm; sonnet; opus for Heavy/arch),
   quota-filtered like run_reviewer_arm; fans out architect + critic passes; synthesizes
   into `docs/handoff/<id>/context.yaml` with REAL `leadv2-acceptance-shape.sh` validation.
2. Diagnose folds in as `--mode diagnose` per the design (same engine, different prompt set).
3. Contract: writes `plan-gate.md` (`status: pass|fail|blocked` + `reason:`) next to
   context.yaml; lead reads only the gate + context.yaml. Never silently pass on
   provider_error/empty_response — mirror review-gate.md semantics.
4. Tests: extend the existing test suites that asserted leadv2-plan.js invariants to
   assert the same invariants against leadv2-plan-run.sh (mirror what 43a634e did for
   review — nothing stranded). The design lists 13 failing assertions to satisfy.
5. Do NOT delete `workflows/leadv2-plan.js` in this lane — deletion + doc flip
   (phases.md §Phase 2, commands/leadv2.md) is a follow-up lane after the engine passes
   its tests, to keep mid-flight lanes unbroken.

Off-limits: leadv2-review-run.sh (read-only reference), routing.yaml semantics,
dispatch scripts.

Deliverable: the engine + tests green (`bash plugins/leadv2/scripts/tests/<suite>`),
summary in docs/handoff/one-path-plan-run-01/build-summary.md, DELIVERABLE_COMPLETE.
