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

## FIX ROUND (2026-08-13 ~00:15Z) — review FAIL 3-4 High
Findings in review-findings.json here. Essence: (1) REBASE onto current origin/main first
— your diff is on a stale base and Row-2 registration re-implements already-landed
STATUS-SURFACE-SHOWS-STALE-TRUTH-01 C5: reconcile with it, keep one implementation;
(2) plugin-sync quarantine must CONVERGE — dedupe by content hash: a permanently
divergent copy quarantined once, not on every sync (reviewer proved 3 syncs = 3 copies);
(3) mutation gate: deleting dispatch-code.sh:3076 must fail your suite — add the
behavioral assertion that catches it; (4) suite registered twice in run-core-offline.sh
— one label. All suites + run-core-offline rc=0 after rebase. DELIVERABLE_COMPLETE.

## TEST-GATE ROUND (2026-08-13 ~00:45Z, per PR02 judge precedent) — Codex, closed scope
Code is committed (e6f8e72). THREE items only:
1. REBASE the worktree branch onto CURRENT origin/main (plan-engine+PR02 merges landed
   after your last rebase; resolve conflicts keeping both sides intact).
2. plugin-sync.sh:167 — sha256sum failure is masked by the pipeline (`|| return 1`
   never fires; two empty hashes compare equal → CHANGED divergent copy treated as
   duplicate). Compute hashes without a masking pipeline; empty hash = hard error.
3. Row-1 mutation gate must be BEHAVIORAL, not grep-on-source: mutate the stamped
   log_path back to pulse.md in a scratch copy and prove liveness goes stale/wrong by
   EXECUTING the registry read path. Gate: rc!=0 on mutated copy, rc=0 on HEAD — both
   runs demonstrated in summary.
All suites + run-core-offline rc=0 after rebase. DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6dff3eaf" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.