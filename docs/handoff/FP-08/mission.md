# FP-08 — freepool arm: premature reap + capability floor (P1)

Repo: canonical leadv2 plugin. Context: docs/leadv2/freepool-backlog.md §FP-08 + §FP-07b.

Live evidence (2026-08-28): dispatch lanes 27434c7a and e9e1ad51 — arbiter/fallback picks
freepool, `product_close` declares `dispatch_terminal no_work cause=empty_diff` ~21-23s
after worker_spawned (journal: worker_spawned 08:57:09 → review_diff bytes=0 08:57:30),
while the freepool worker (claude -p via FCC proxy) is still running. Lane cb411cf7 proved
the arm CAN finish bounded tasks when given time. Compare the GLM arm: product_close waits
via `waiting_worker ... waited=Ns` beats until terminal or timeout.

Fix, two parts, in plugins/leadv2/scripts/leadv2-dispatch-code.sh (+ libs):
1. WAIT UNIFICATION: the freepool arm's worker handle (freepool-coder.sh bg workbench
   handle, e.g. `260828-115709-e9e1ad51-54f3`) must be tracked by the same waiter the glm
   arm uses (waiting_worker beats until worker terminal or FREEPOOL_TIMEOUT, default from
   the glm arm's timeout). Find why the freepool handle scheme is invisible to product_close
   (journal shows `worker_liveness=unknown ... action=proceed_legacy`) and make liveness
   resolvable: known handle => wait; only a provably-dead worker or timeout ends the wait.
2. CAPABILITY FLOOR (config-driven, never a hand-kept exclusion list): freepool is
   rank-eligible for the WORKER role only when TaskEstimate work_kind maps to role=bulk
   OR class in {Trivial,Light}. For class>=Standard implement/build work, freepool ranks
   BELOW codex/sonnet until FP-04's quality gate flips a config key
   (e.g. freepool-arm.yaml `capability_floor: bulk_only|full`). Journal
   `arm_floor_applied arm=freepool reason=<class/work_kind>` whenever it demotes.
   Wire through the arbiter scoring input or candidate-chain builder — whichever layer
   already owns eligibility — do not add a parallel mechanism.

Tests (plugins/leadv2/scripts/tests/, hermetic, no live proxy):
(a) stub freepool worker finishing at t+40s with a real diff -> waiter must NOT declare
    no_work early; terminal reflects the diff.
(b) class=Standard work_kind=build -> freepool never selected even when cheapest; assert
    the `arm_floor_applied` journal line.
(c) work_kind bulk/simple -> freepool still selectable.
(d) NEGATIVE CONTROL declared in suite header and RUN red: mutation removes the floor ->
    test must catch freepool winning a Standard build.
Run touched suites + bash -n; raw output in report. Add EXTRA_SUITE_MAP rows in
tests/run-all.sh so CI selects the new suite on dispatch-code changes.

Commit: fix(leadv2): FP-08 freepool wait unification + capability floor.
Report: docs/handoff/FP-08/report.md (max 250 words), end DELIVERABLE_COMPLETE.
