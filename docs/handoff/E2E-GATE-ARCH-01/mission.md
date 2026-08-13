# E2E-GATE-ARCH-01 — e2e gate must test the LANE, one gate at a time

Ledger row SD-E2E-GATE-LOAD-FLAKE-01 (persona-engine docs/leadv2/scheduled-decisions.md).
Proven 2026-08-12: dispatch-051b9490 and dispatch-54aaa0bf both died cause=e2e_regression
while their own suites passed rc=0 in isolation. The gate log line
`repo=/Users/kostiantyn.vlasenko/Projects/leadv2` proves the gate runs suites against
MAIN, not the lane worktree — so a lane can neither benefit from its own fixes nor
avoid parallel-lane load flakes.

Fix in plugins/leadv2/scripts/leadv2-dispatch-product-close.sh (gate block ~:1660-1680):
1. Run the e2e suite (run-core-offline.sh) against the LANE WORKTREE checkout — the
   tree that contains the lane's own commits — not the main checkout.
2. Take a GLOBAL flock (one gate at a time across all lanes; lock file under
   ~/.claude/cache/, wait with a bounded timeout, on timeout log and retry once —
   never fail the lane on lock contention alone).
3. Keep the existing timing-suite kill-switches untouched.

Rules:
- Behavioral hermetic tests (mktemp sandbox, model: tests/test-plugin-reliability-02.sh):
  (a) gate invoked for a lane whose worktree fixes a suite that is red on main → gate
  passes (proves lane-tree testing); (b) two concurrent gate invocations serialize
  (flock proof). Red/green: each test must FAIL with your fix reverted.
- Full `bash tests/run-core-offline.sh` rc=0 before DELIVERABLE_COMPLETE.
- Off-limits: leadv2-plan-run.sh, workflows/, docs/phases.md, repo leadv2.md files.
- NOTE: --glm-failures router behavior is BY DESIGN (F1 spoof fix, dispatch-code.sh:74,
  :3242) — do not touch it.

Deliverable: commits + docs/handoff/E2E-GATE-ARCH-01/summary.md (what changed, test
names, red/green proof lines), then DELIVERABLE_COMPLETE.
