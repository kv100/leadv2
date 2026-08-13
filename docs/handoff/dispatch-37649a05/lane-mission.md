# PLAN-FOLLOWUPS-01 — fix the 4 High judge caveats on the plan engine

These are the BLOCKING preconditions of the plan doc-flip (ledger SD-ONE-PATH-ROLLOUT-01).
Source of truth: docs/handoff/ONE-PATH-PLAN-RUN-01/followups.md. Fix all four:

1. plugins/leadv2/scripts/leadv2-plan-run.sh:436 — arm loop must CONSUME
   refused_quota / refused_peak_hours / refused_channel_down refusals and spill to the
   next :ok: arm instead of treating a refusal as terminal. Model: the review engine's
   candidate loop in leadv2-review-run.sh (same repo) — reuse its pattern.
2. plugins/leadv2/scripts/leadv2-plan-run.sh:373 — extract_plan_yaml expects marker
   THEN fence but the mission prompt tells arms fence THEN marker. Accept BOTH orders.
3. plugins/leadv2/scripts/lib/leadv2-context-merge.py:36 — a non-dict `acceptance`
   must be a nonzero-exit hard error (never silently accepted); when merging, preserve
   existing acceptance.authored_at.
4. plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:511 — review-floor /
   _best_effort_floor_pool results must be filtered by DISPATCHABLE_PLAN_ARMS when
   resolving for the plan phase (haiku must never enter the planning pool).

Rules:
- Behavioral hermetic tests (mktemp sandbox) for each fix; red/green: each test must
  FAIL when its fix is reverted. Grep-on-source tests are rejected at review.
- Item 1+2 verification must include ONE run against real arm output shape: use the
  captured fixtures in docs/handoff/ONE-PATH-PLAN-RUN-01/ (arm outputs from the r2
  verify run) — not a hand-invented mock.
- Full `bash tests/run-core-offline.sh` rc=0 before DELIVERABLE_COMPLETE.
- Off-limits: workflows/, docs/phases.md, repo leadv2.md files (doc-flip is a separate
  lane), leadv2-dispatch-code.sh.

Deliverable: commits + docs/handoff/PLAN-FOLLOWUPS-01/summary.md (per-item: fix,
file:line, test name, red/green proof line), then DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-37649a05" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.