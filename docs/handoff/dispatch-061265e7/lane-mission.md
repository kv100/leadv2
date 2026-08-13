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

## Round 2 addendum (2026-08-12 ~13:30Z) — the real defect is harness hermeticity

Your round-1 fixes are MERGED to main (e183dd2) and both suites pass INSIDE a lane
worktree — but on the MAIN tree they still fail:
- p1 "quota refusal advances chain": glm refused ok, but the chain does NOT advance to
  codex on main → rc=2. On a worktree the same test spawns codex fine. Suspect: codex
  arm admission consults workspace/$PWD-scoped state (codex CLI status is
  workspace-scoped and can falsely report dead — known trap), or another repo-root-keyed
  store. Cases "launcher crash", "duplicate refusal", "racing reserve", "lockout write"
  fail the same way.
- vocab case1 "dispatch exited 1": full dispatcher invocation exits 1 on main only;
  cases 2-6 now pass everywhere.

Required fix: make BOTH suites hermetic — every state the dispatcher reads (codex/GLM
arm admission, dispatch ledger, quota lockouts, phase records, journals) must be pinned
to the test sandbox regardless of which tree runs them. Stub arm admission probes; a
unit test must never depend on live codex CLI workspace state. Do not change production
dispatch logic.

Green proof required: `bash plugins/leadv2/scripts/tests/run-core-offline.sh` rc=0 ON
THE MAIN TREE (~/Projects/leadv2), run twice consecutively (proves no self-pollution),
full tail attached to summary. Never weaken assertions to pass.

Off-limits: workflows/, leadv2-review-run.sh, leadv2-plan-run work in the
ONE-PATH-PLAN-RUN-01 worktree.

Deliverable: fix commits + docs/handoff/E2E-GATE-RESIDUE-01/summary.md (root-cause per
suite + rc=0 proof), DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-061265e7" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.