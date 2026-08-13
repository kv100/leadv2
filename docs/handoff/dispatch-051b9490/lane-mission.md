# E2E-GATE-P1-REGRESSION-01 — main is red: dispatch refusal-chain + no-work-terminal suites

Symptom (verified 2026-08-12 on clean main, rc=1):
`plugins/leadv2/scripts/tests/run-core-offline.sh` fails on exactly two checks:
1. "dispatch refusal fallback chain" — test-routing-enforcement-p1.sh: multiple cases die
   with rc=2 and journal line `dispatch_classified task=<sig> class=non_product
   reason=explicit_mission_fast_path kind=unknown` (quota refusal advance, peak-hours
   advance, launcher crash, duplicate refusal, racing reserve, quota lockout write side).
2. "product-close waits for worker exit" — test-no-work-terminal.sh: 1 of 43 fails:
   `revive_blocked_by_gate waited to timeout instead of finalizing original handle`.

This is PRE-EXISTING on main (baseline run without any lane commit: rc=1). It just killed
lane a88918ee (ONE-PATH-PLAN-RUN-01) via e2e_gate verdict=fail — an unrelated execution.

Task:
1. Root-cause: bisect or inspect recent main merges touching leadv2-dispatch-code.sh /
   classification (suspects: PHASES-ARE-THE-ONLY-PATH-01 merge c5acfac, phase-precondition
   guard e55c0ef, quota-gate fallback c5f60ee, glm_quota_gate_80 test 361714a). The
   `explicit_mission_fast_path` classification appears to short-circuit the refusal-chain
   semantics these tests assert.
2. Decide honestly: code regression (fix the code) vs tests asserting retired behavior
   (fix the tests + say so). Evidence in the summary either way.
3. Green proof: `bash plugins/leadv2/scripts/tests/run-core-offline.sh` rc=0 on main.
   Never weaken an assertion just to pass — that is the lying-green disease.

Off-limits: workflows/, leadv2-review-run.sh, the ONE-PATH-PLAN-RUN-01 worktree.

Deliverable: fix commit(s) + docs/handoff/E2E-GATE-P1-REGRESSION-01/summary.md with
root-cause + rc=0 proof line, DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-051b9490" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.