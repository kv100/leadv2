# PLUGIN-RELIABILITY-01 — audited product-close/dispatch defects (5 + 1 found today)

All confirmed 2026-08-12 (audit with file:line + two live incidents in one day).

1. BREAKS-LANES — `leadv2-dispatch-product-close.sh:780` pc_worker_alive marks a worker
   dead from meta.yaml status + registry absence WITHOUT `kill -0` on the recorded pid.
   Twice today a lane got terminal=dead while its glm-coder `__supervise` process kept
   running 30-50 min, holding the global GLM lock (had to be pkill'ed by hand). Fix:
   liveness = pid check first (kill -0 on the supervise pid from the run handle), meta
   status only as a secondary signal; on terminal=dead ensure the worker process group is
   actually gone (TERM, wait, KILL) before writing the ledger row.
2. Worktree lanes are review-blind — claude-subsession dies `role file not found: critic`
   because lane worktrees do not materialize `.claude/agents/`. Today every in-lane
   Phase-5 ended parked all_review_arms_unavailable and review had to be run manually
   from the main root. Fix in leadv2-review-run.sh / subsession role resolution: fall
   back to the main checkout's agents dir (derive via git worktree list / common-dir)
   when the role file is absent in WORK_ROOT.
3. Architect prepass parks silently — dispatch-code.sh:405-416: 420s×2 timeouts → park,
   no interrupt, no founder-visible signal. Fix: journal a loud `prepass_parked` line +
   write a questions/ pending entry so supervise surfaces it; make timeout configurable
   per class.
4. Malformed/truncated meta.yaml → full 4200s false wait (product-close.sh:762-780):
   empty status defaults to keep-waiting even with pid gone. Fix: pid-gone + unparseable
   meta = dead after one grace re-read.
5. Cosmetic: router_v2 reorder failure at quota refusal is silent (dispatch-code.sh:
   3593-3614) — journal `reorder_failed rc=` so refusal chains are debuggable.

Tests: hermetic (mktemp sandbox, no HOME/real-repo state — follow the pattern shipped in
test-routing-enforcement-p1.sh header today), one suite per fix, wired into
run-core-offline.sh. Full run-core-offline rc=0 on main before DELIVERABLE_COMPLETE.

Off-limits: workflows/, leadv2-plan-run.sh followups (separate gated lane), repo docs.

Deliverable: commits + docs/handoff/PLUGIN-RELIABILITY-01/summary.md with per-defect
root-cause & proof, DELIVERABLE_COMPLETE.
