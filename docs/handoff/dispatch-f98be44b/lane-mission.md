# STATUS-SURFACE-BATCH-01 — SwiftBar + statusline P1 batch (4 backlog rows)

Four queued P1 rows, one surface family (full intents in `rows.md` in this directory):

1. MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 — SwiftBar shows dead lanes and raw sig8
   hash names instead of founder task-ids.
2. STATUSLINE-FLICKER-PARTIAL-CACHE-01 — statusline flickers between full and partial
   render (founder: "статуслайн скачет").
3. STATUSLINE-SHOWS-LANES-QUESTIONMARK-01 — renders "lanes ?" while lanes exist.
4. SD-STATUSLINE-BURN-FIRSTCLASS-01 — burn segment gets first-class width budget.

Rules:
- PREMISE-CHECK each row first against the current scripts (leadv2-status-surface*.sh,
  leadv2-lane-status-line.sh, supervise-loop cache files) — a row may already be fixed;
  if so, mark it "already-fixed" in the summary with file:line evidence and skip.
- Fix the still-real ones. Surface truth source is docs/leadv2/active.yaml + the
  dispatch ledger; dead-lane display must respect the same liveness rule as
  supervise-loop (log mtime, not status fields).
- Tests: extend tests/test-status-surface-*.sh (hermetic, mktemp sandbox) covering each
  fixed row; suite rc=0.

Off-limits: leadv2-dispatch-code.sh, leadv2-dispatch-product-close.sh, hooks/ (owned by
parallel lanes CONTINUATION-GUARD-01 and E2E-GATE-RESIDUE-01 right now).

Deliverable: commits + docs/handoff/STATUS-SURFACE-BATCH-01/summary.md (per-row verdict:
fixed / already-fixed / blocked+why, with proof lines), DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-f98be44b" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.