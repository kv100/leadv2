# PHASE-DISCIPLINE-01 build mission (Gate-1 approved: Slice A+B)

Repo: this repo (canonical leadv2 plugin). Read FIRST, bounded:
- docs/handoff/PHASE-DISCIPLINE-01/context.yaml — decisions D1-D7, off_limits, steps. BINDING.
- docs/handoff/PHASE-DISCIPLINE-01/retro-review.md — the two FAILs being fixed (steps 5-6).

Implement plan_steps 1-7 from context.yaml in plugins/leadv2/scripts/:
1. dispatch-code: deterministic TaskEstimate->class map + persisted admission receipt
   (task id + mission digest) + journal `task_class=<c> route=<dispatch|phases> source=<s>`
   once per intake. Explicit class escalate-only. Classifier failure -> Standard/phases.
2. Flip REQUIRE_PHASES effective default to enforce for class>=Standard (Light
   unaffected); Phase-4 re-entry admitted only with same-task plan+Gate-1 records
   (via leadv2-phase-record.sh) + matching receipt. LEADV2_REQUIRE_PHASES=0 kill
   switch keeps byte-identical semantics.
3. backlog-pump: classify immediately after successful claim, before launch.
   Light -> dispatch as today. Standard/Heavy -> session-spawner ADOPT path (Slice B):
   accept the pump's held claim, ensure lane worktree, start ONE full-cycle runner,
   atomically replace placeholder pid; release/unclaim on every pre-spawn failure.
   If adopt path unavailable at runtime -> phases_required refusal surfaced via the
   existing rc=3 escalation-question path (Slice A fallback), never bare dispatch.
4. Gate-1 semantics: Heavy/high-risk -> blocking async question (leadv2-ask), no
   timeout acceptance in any mode; Standard non-high-risk -> timeout auto-accept
   journaled `gate1_auto_accepted` vs `answered`. Align docs/phases.md +
   commands/leadv2.md with actual gate1-prompt.sh behavior.
5. FIX a38a5bd: export FREEPOOL_ROLE at the real dispatch call site from
   TaskEstimate.work_kind (review->review, build->implement, docs/bulk->bulk);
   demote mission-text regex to narrow direct-invocation fallback (must not match
   noun phrases like "implement the code-review dashboard"); e2e test captures the
   env actually received by freepool-coder.sh bg (stub binary).
6. FIX 341b80a: regression fixture installing route-arbiter/quota-live/freepool-gate
   via relative+chained per-file symlinks in a tmp layout; assert canonical config
   discovery (arbiter rc!=65); mutation restoring logical-path lookup must go red.
7. Verify: bash -n all changed; run the touched test suites + negative control:
   a Standard-shaped mission through the pump path must NOT spawn a bare worker
   (journal shows receipt + adopt/refusal). Paste raw outputs in the report.

off_limits (from context.yaml): kill-switch semantics; arbiter rc 64-67; task-judge
prompt lexicon; provider ladders/quotas/roster order; WIP=1; no new daemon.

Commit granularity: one commit per step-group (1-2, 3-4, 5, 6) with tests in the
same commit. Message prefix: feat(leadv2): PHASE-DISCIPLINE-01 — <step>.
Report: docs/handoff/PHASE-DISCIPLINE-01/build-report.md (max 400 words, per-step
diffstat + raw test output + negative-control evidence), end with DELIVERABLE_COMPLETE.
