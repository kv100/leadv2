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

## Round 3 addendum (2026-08-12 ~14:45Z) — one store still shared: the HOME ledger

Round-2 edits are good (env unset + wrapper + early-verdict kill; vocab suite now rc=0
everywhere) but p1 case 3 "quota refusal advances chain" HANGS >25 min: the dispatcher
inside the test still uses the REAL shared ledger dir — DISPATCH_LEDGER_DIR defaults to
`${HOME}/.claude/cache/dispatch-ledger` (leadv2-dispatch-code.sh:374-375,
CACHE_BASE="${LEADV2_DISPATCH_CACHE_DIR:-${HOME}/.claude/cache}") — and blocks on its
flock (`.leadv2.dispatch.lock`), which live dispatches from OTHER sessions hold.

Surgical fix: in the p1 suite header (next to the round-2 unset block) export
`LEADV2_DISPATCH_CACHE_DIR="${TMP_ROOT}/cache"` so ledger, quota-lockout files and any
other CACHE_BASE-derived store live in the sandbox. Audit the suite for any other
HOME-scoped path the dispatcher touches (glm-runs handles etc.) and pin those too.
Prove: p1 suite completes < 3 min with rc=0, run twice.

Green proof required: `bash plugins/leadv2/scripts/tests/run-core-offline.sh` rc=0 ON
THE MAIN TREE (~/Projects/leadv2), run twice consecutively (proves no self-pollution),
full tail attached to summary. Never weaken assertions to pass. NOTE: a foreign session
runs its own lane on this machine — do not assume an idle machine; hermetic tests must
pass anyway.

Off-limits: workflows/, leadv2-review-run.sh, leadv2-plan-run work in the
ONE-PATH-PLAN-RUN-01 worktree.

Deliverable: fix commits + docs/handoff/E2E-GATE-RESIDUE-01/summary.md (root-cause per
suite + rc=0 proof), DELIVERABLE_COMPLETE.
