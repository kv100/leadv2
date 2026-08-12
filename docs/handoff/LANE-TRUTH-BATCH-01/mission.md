# LANE-TRUTH-BATCH-01 — three queued P1 rows on lane registry/liveness truth

Full intents in `rows.md` in this directory:
1. LANE-LIVENESS-BLIND-TO-FUNNEL-PATH-01 — supervise-loop declares funnel-dispatched
   lanes dead:no_handoff_dir.
2. LANE-REGISTRATION-ONLY-ON-FANOUT-PATH-01 — lanes launched via leadv2-dispatch-code.sh
   directly are invisible to the registry/supervise surfaces.
3. UNLANDED-FIXES-IN-USER-SCRIPTS-COPIES-01 — leadv2-plugin-sync.sh DIRECTION-SAFETY
   blocks landing fixes made in user-script copies; potential lost work.

Rules:
- PREMISE-CHECK each row first against the CURRENT tree — the reliability merges of
  2026-08-12 (pid-file liveness, registry guards) may have changed the ground truth;
  mark already-fixed rows with file:line evidence and skip.
- Liveness truth source: log mtime / pid-file per today's PLUGIN-RELIABILITY-02 work —
  do not reintroduce status-field trust.
- Tests: behavioral, hermetic (mktemp sandbox); the red/green pattern from
  test-plugin-reliability-02.sh is the model. Grep-on-source tests are rejected.
- Full `run-core-offline.sh` rc=0 before DELIVERABLE_COMPLETE.

Off-limits: workflows/, leadv2-plan-run.sh followups (separate gated lane), repo docs
outside your summary.

Deliverable: commits + docs/handoff/LANE-TRUTH-BATCH-01/summary.md (per-row verdict
fixed / already-fixed / blocked+why with proof), DELIVERABLE_COMPLETE.

## RESUME NOTE (2026-08-12 ~20:55Z)
Previous worker died after editing leadv2-active-registry.sh / leadv2-dispatch-code.sh /
leadv2-plugin-sync.sh (uncommitted in the lane worktree — check `git status` FIRST and
continue from those edits). Missing: behavioral tests + summary.md + commits.
