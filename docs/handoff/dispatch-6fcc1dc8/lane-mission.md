# Mission: ARBITER-SCORING-DESIGN-01 implementation, Step 1 (additive, off by default)

Spec (READ FULLY FIRST, do not skip any section): `docs/handoff/F1-ARBITER-SCORING-20260907/design.md`
in persona-engine (already committed at `f88e15c3c` and `e678b4eb2`).

Founder go-ahead for editing the shared plugin tree is already granted (this is Step 0 of §8's
rollout table — treat it as satisfied; do not re-ask).

## Scope: implement ONLY Step 1 of §8's rollout plan. Do not implement steps 2-4.

Step 1 is additive and defaults OFF (`enabled: false`). It must not change any live arm pick.

1. `~/Projects/leadv2/plugins/leadv2/config/leadv2-routing.yaml`:
   - Add `capability_fit: { enabled: false }` (or the exact key design.md specifies — read §4-§7
     for the literal schema) alongside the existing `+100` penalty block.
   - Add a `capability:` tier (1-4) to every capability_matrix cell, per §4's mapping — do not
     invent tiers, use the design doc's assignment for every named arm (glm-flash, glm, freepool,
     haiku, codex/volume, codex/standard, sonnet, opus, fable).
   - Rewrite the stale comment block the design doc flags at routing.yaml:270-301/:296 (R5) in the
     SAME commit — it currently cites a dead `_hard_flag … :79` reference.
   - Set `source_confidence.heuristic = 0.4` exactly (Leadmain's reviewed decision, recorded in
     design.md §12 OQ1 — glm-flash keeps ≤30-line missions until the judge is live).

2. `~/Projects/leadv2/plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`:
   - Implement §6's decision function (read it verbatim — it is written in the arbiter's own
     variable names) as new code, gated behind `LEADV2_ARBITER_CAPABILITY_FIT` (default off,
     matching `capability_fit.enabled` from the yaml). When off, behavior must be byte-identical
     to today (verify with the existing `tests/test-router-v2-headroom-order.sh` — it is the only
     existing arbiter test and MUST stay green).
   - Emit `fit_pick=` / `fit_differs=` tokens on every decision line, per §9.2, even while off is
     the operative mode (shadow-computed, not shadow-gated on a separate flag yet — that shadow
     env var is Step 3, not this step. For Step 1 just wire the function and its tokens; it is
     inert until `enabled: true`, which is Step 4 and NOT part of this mission).

3. Do NOT touch: `task_class`'s `sizes:` filter role (R1 — this must not be edited), freepool
   floor mode, `UNKNOWN_PROBE_PENALTY`, failure-memory demotion, `effort_matrix`, the legacy
   resolver / kimi arm, or any persona-engine file. Out-of-scope list is §11 of design.md — read
   it, it is authoritative.

4. Write `tests/test-router-v2-capability-fit.sh` (new, does not exist yet) covering §9.2's
   differ/match table: for each row, construct the described input and assert the expected
   `fit_pick`/`fit_differs` value. Every one of the ~8 rows in §9.2 must have a corresponding test
   case. A negative control per §9's discipline: prove a deliberately-mutated capability tier or
   confidence value actually executes (print the literal token it produces, e.g. `req_eff=3.0
   conf=0.9`), not just that a test suite passed — this is the strongest form Leadmain already
   praised in the design's own §9.2/§9.3, reuse it exactly.

## Acceptance (I run this myself before accepting the diff — do not claim it passed for me)

- `tests/test-router-v2-headroom-order.sh` still green (byte-identical picks with the flag off).
- New `tests/test-router-v2-capability-fit.sh` green, one case per §9.2 row.
- A live or synthetic-but-labeled dry run showing `fit_pick=`/`fit_differs=` tokens appear on
  arbiter output while `enabled: false` still leaves the actual `arm=` pick unchanged.
- routing.yaml comment rewrite (R5) landed in the same commit as the capability_fit addition.
- Report `checked=N` for every claimed count, per this project's own measurement discipline.

## Explicitly NOT this mission

Steps 2-4 of §8 (task-judge `complexity_basis`, dispatcher `complexity_source`, the shadow env
var, and flipping `enabled: true`) are separate follow-up missions, dispatched after this one is
reviewed and accepted. Do not get ahead of scope.

Report back with a diff summary, the test output, and explicit `checked=N` counts. Lead (this
session) does the review and acceptance against §9.2/§9.3 — you are not self-certifying this as
done, you are handing it back for that review.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6fcc1dc8" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.