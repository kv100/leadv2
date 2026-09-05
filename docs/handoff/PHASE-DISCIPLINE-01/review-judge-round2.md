# PHASE-DISCIPLINE-01 — judge re-check, fix round 2 (18096b9)

> Scratchpad fallback: `guard-worktree-scope.sh` blocks writes to the leadv2 checkout.
> Lead: copy to `docs/handoff/PHASE-DISCIPLINE-01/review-judge-round2.md`.

**C1 — PASS.** Six configs re-probed against the new guard:
warn/Light rc0 (`phase_precondition_warn`) · warn/Standard rc0 (warn) · explicit-1/Standard rc1
(full scope, 8 missing) · unset/Light rc0 (warn) · unset/Standard rc1 (`missing=classify,plan,gate1`
— pre-build scope) · `=0` rc0. `--full` is never emitted now.

**C2 — PASS.** context.yaml D5 reads "Slice A+B сразу, adopt default-ON, negative control = never a
bare worker (session_spawned OR phases_required)". Shipped `leadv2-backlog-pump.sh:742`
`LEADV2_BACKLOG_PUMP_ADOPT:-1` matches.

**C3 — PARTIAL.** `EXTRA_SUITE_MAP` works: simulated `--scope changed` over 6090906..HEAD selects
test-phase-precondition, test-gate1-discipline, test-admission-class; all 6 mapped suites exist.
Two gaps: `leadv2-route-arbiter` is unmapped (`grep -c route-arbiter tests/run-all.sh` = 0), so the
D7 symlink fixture is still never selected; and no suite declares a named negative control
(`grep -i "negative control|MUTATION"` = 0 in the three new suites). Turn cap hit before a fresh
mutation run; round-1 evidence stands that gate1-discipline has teeth (mutated → rc1, 11/1).

**H4 — FAIL.** `seed_receipt` now derives sig8 from the real digest pipeline — the magic literal is
gone. But `T6_BUILD` ("deliberately different from the intake mission") is a dead variable
(`grep -c T6_BUILD` = 1, its own assignment); the assert at :120 still runs on the **intake** sig8.
Production asserts under the **build**-mission sig8, and no task_id→sig8 receipt resolution was
added to dispatch-code. The join remains unproven — the test now looks like it covers it.

**VERDICT: C1 PASS · C2 PASS · C3 PARTIAL · H4 FAIL.**

DELIVERABLE_COMPLETE
