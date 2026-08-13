# E2E-GATE-RESIDUE-01 — two remaining red core-offline suites on main

Context: E2E-GATE-P1-REGRESSION-01 (merged, e101872) fixed 2 of 4 red suites. Idle-main
full run (2026-08-12, /tmp/main-core-offline.log) still shows 3 FAILED; one (refusal
chain) is fixed by that merge. Fix the remaining two:

1. "dispatch arm vocabulary (kimi retirement)" — harness dies:
   `harness.sh: line 75: _dispatchable_arms: command not found`, then case2/case3 chains
   collapse to 'sonnet' with mismatch_emitted=1. NOT test-only: real dispatches journal
   `dispatchable_arms_read_failed reason=importlib_read_failed` +
   `routing_config_degraded ladder=legacy_hardcoded` (see
   docs/leadv2/tasks/dispatch-a88918ee/journal.md 10:31Z). Root-cause the rename/removal
   of `_dispatchable_arms` in leadv2-dispatch-code.sh history; decide honestly: restore
   the function/read path so importlib read works again (preferred if prod routing is
   genuinely degraded) AND align the test harness with the current API. The degradation
   fallback must stay (it kept dispatch alive), but the primary read should work.

2. "Codex quota guardrails (effort/circuit/hook)" — 23/24 pass; failing case:
   `f2 codex usage-limit -> circuit opened with parsed horizon, 1 spawn` (rc=2,
   state='closed', jcount='1', spawns='1'). Determine flake vs regression: run the suite
   3x in isolation; if deterministic, root-cause against leadv2-codex-session-runner.sh
   circuit logic; if env-dependent (codex CLI state), make the case hermetic.

Green proof required: `bash plugins/leadv2/scripts/tests/run-core-offline.sh` rc=0 on
main, full output attached to summary. Never weaken assertions to pass.

Off-limits: workflows/, leadv2-review-run.sh, leadv2-plan-run work in the
ONE-PATH-PLAN-RUN-01 worktree.

Deliverable: fix commits + docs/handoff/E2E-GATE-RESIDUE-01/summary.md (root-cause per
suite + rc=0 proof), DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2d422889" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.