# PLUGIN-RELIABILITY-01 — audited product-close/dispatch defects (5 + 1 found today)

## FIX ROUND (2026-08-12 ~19:15Z) — review FAIL: 3 Critical + 4 High

Findings: docs/handoff/PLUGIN-RELIABILITY-01/review-findings.json (in the lane worktree).
Blocking essence:
- `_pc_process_alive` / `_pc_reap_worker` use unscoped `pgrep -f "$handle"`: SELF-MATCH
  (the close gate's own argv contains the handle → always "alive", and reap would
  SIGKILL the close gate itself) and can match/kill UNRELATED processes. Fix: track the
  worker's own pid/pgid from the spawn record (glm-runs handle dir has the pids), match
  by exact pid + verify its argv, never by substring pgrep of the whole host.
- prepass-parked path calls leadv2-ask.sh SYNCHRONOUSLY with --timeout 1800 inside
  cmd_resolve (dispatcher can hang 35 min) and then discards the answer, exit 3
  unconditionally. Fix: fire-and-forget question write (or short timeout <=60s), honor
  the retry answer or drop the option.
- claude-subsession.sh:190 tests `== "agents"` so ROLE_SOURCE=agents_worktree_fallback
  injects raw YAML frontmatter. Fix the comparison to accept the fallback source.
- empty-status→dead needs a run-age/meta-existence grace guard (a just-spawned worker
  without meta.yaml must not be declared dead).
- Tests MUST be behavioral: source the real functions / run claude-subsession.sh and
  assert observable behavior (a fake worker process, a fake handle collision, the
  self-match case). Grep-on-source tests are forbidden — that is the lying-green
  disease and it is why round 1 failed.
All suites + run-core-offline rc=0. Then DELIVERABLE_COMPLETE.

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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-35b5a299" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.