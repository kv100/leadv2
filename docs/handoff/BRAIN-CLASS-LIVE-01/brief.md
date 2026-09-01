# BRAIN-CLASS-LIVE-01 — class is computed by the judge on the DEFAULT path; a declared class is a floor

Umbrella: `docs/handoff/ROUTER-BRAIN-01/design.md` (read §A and the "What is true today" table first).
LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BRAIN-CLASS-LIVE-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/leadv2-task-judge.sh,plugins/leadv2/scripts/leadv2-admission-class.sh,plugins/leadv2/scripts/lib/leadv2-brain-record.sh,plugins/leadv2/scripts/tests/test-brain-class-live.sh,tests/run-all.sh,docs/handoff/BRAIN-CLASS-LIVE-01/
Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The defect
`leadv2-task-judge.sh` (haiku, schema-validated TaskEstimate) exists and is tested, but the default
`resolve_arm` path in `leadv2-dispatch-code.sh` never calls it — it lives only behind
`LEADV2_ROUTER_V2` (default 0). So every lane's class is whatever the lead typed in `--task-class`.
Today every dispatch in this repo was `--task-class standard` by hand. Founder order: every task
goes through the complexity estimator.

## Do
1. Call the judge on the default path, before arm resolution, for every dispatch (cached per
   mission hash as it already is). Fail-open: judge error or timeout → `class_source=declared_fallback`
   journaled, declared class used, never a refusal.
2. `--task-class` becomes a **floor**: `class = max(declared, computed)` on the ladder
   Trivial < Light < Standard < Heavy < Strategic. Journal every escalation:
   `class_escalated task=<sig8> from=<declared> to=<computed> because=<top signal from the estimate>`.
   A computed class BELOW the declared one never lowers it; journal `class_floor_held`.
3. New `scripts/lib/leadv2-brain-record.sh`: writes `docs/handoff/<task>/brain.yaml`
   (`class`, `class_source`, `estimate` summary, `phases` — for this lane, phases = the existing
   hardcoded list for the class as `_phase_precondition_guard` knows it today; later lanes extend) and
   emits ONE journal line `brain_decision task=<sig8> class=<c> class_source=<s> phases=<csv>
   reason=<rule>`. `_phase_precondition_guard` and `leadv2-admission-class.sh` read the class from
   `brain.yaml` when present, else fall back to today's behaviour.
4. Suite `test-brain-class-live.sh`: (a) a mission whose LANE_WRITES touches `hooks/` + `safety`
   paths with `--task-class light` → `class_escalated … to=Standard|Heavy`; (b) a trivial mission
   declared Heavy → `class_floor_held`, class stays Heavy; (c) judge stubbed to fail → `declared_fallback`
   and the dispatch proceeds; (d) `brain.yaml` exists and the `brain_decision` line names the class
   the guard then enforces. Mutation negative control, RUN and paste red: make the judge call
   unconditional-skip (`return 0` before it) → (a) and (d) red. Register in `tests/run-all.sh`.
5. Evidence in `report.md`: suite green, control red, and ONE real dispatch (`--force`, any queued
   brief, then kill the worker) showing the `brain_decision` line in `docs/handoff/dispatch-*/`.

## Do NOT
- Put arm/model/quota vocabulary into the judge prompt (invariant in the judge header).
- Touch the arbiter, effort matrix, review pool or quota code — those are lanes 3 and 4.
- Change `LEADV2_ROUTER_V2` semantics; the judge call is lifted out of it, the flag stays for the rest.
