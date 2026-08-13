# ONE-PATH-PLAN-RUN-01 — build leadv2-plan-run.sh (Plan consolidation)

## FIX ROUND (2026-08-12 ~17:30Z) — review verdict FAIL: 1 Critical + 6 High

The engine is built and reviewed; fix the blocking findings in
`docs/handoff/ONE-PATH-PLAN-RUN-01/review-findings.json` (in the lane worktree). Key:
diagnose mode validates the PLAN schema instead of root_cause+confidence (always exits
blocked); `planner` unbound under set -u in diagnose mode; retry rewrites the mission
file it just appended failure reasons to; critic reads plan-arm-codex.yaml hardcoded
fallback in cross-arm case; skeleton write clobbers pre-existing valid context.yaml
before any arm runs; both diagnose suites are grep-on-source only — replace with tests
that EXECUTE --mode diagnose; test-plan-run-contract.sh:224 regex needs single-space
`claude -p`; remove/fix the stray failing test-diagnose-no-pe-constants.sh. Every fixed
finding needs an executing test. All suites rc=0. Then DELIVERABLE_COMPLETE.

Goal: implement the Plan half of ONE-PATH-EVERYWHERE-01 — a sole-owner bash engine
`plugins/leadv2/scripts/leadv2-plan-run.sh`, mirroring the shipped review engine
`plugins/leadv2/scripts/leadv2-review-run.sh` (read it first; reuse its arm-pool /
quota-filter / journal patterns, do not fork new conventions).

Authoritative design: `docs/handoff/one-review-path-2026-08-06/design-plan-diagnose.md`
(census rebuilt from source). Its §0 "missing prerequisite" gap is now CLOSED — the files
were recovered into the same dir: read `design.md` (one-review-path consolidation design)
and `mission-build-r1.md` too; where design-plan-diagnose.md §7 raised conditional
questions against the unseen design.md, resolve them against the real file.

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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-3f4b3050" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.