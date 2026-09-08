Part A ONLY of row d2823c51e670 (ARM-RECEIPTS-AND-HISTORICAL-IMPORT-01). Part B (dispatcher wiring)
is owned by another lane — do NOT touch plugins/leadv2/scripts/leadv2-dispatch-code.sh or
lib/leadv2-route-arbiter.sh. If Part A turns out to need them, STOP and report instead of editing.

Read first: ~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md §P3,
then /tmp/m-p3-lane.md (full brief).

Build:
1. plugins/leadv2/scripts/lib/leadv2-arm-receipts.sh — append-only writer + reader.
   - Ledger path ~/.claude/state/leadv2/arm-receipts.jsonl, OUTSIDE the git tree.
   - Writer: one O_APPEND single-write() per record (single printf/write call), never rewrite in place.
   - Key: lane_id + decision_id + attempt_id. sig8 is NOT a key (collides across resume/arm-advance).
   - Fields: launch tuple (kind, role, arm, model, tier, effort), account_label (label only:
     personal/work — never id/email/token), timestamps, duration, 4 token counters, turns, outcome,
     fallback_depth, usage_src, usage_is_estimate.
   - Reader returns sums AND n (sample count) always.
   - Leave ONE named seam (a function) documented in a comment, meant for _dl_note
     (leadv2-dispatch-code.sh:2164) to call at attempt-open/attempt-close. Do not wire it yourself.

2. plugins/leadv2/scripts/leadv2-arm-receipts-import.sh — historical importer.
   - Walks: claude costs.yaml, glm ~/.claude/cache/glm-runs/*/meta.yaml,
     freepool ~/.claude/cache/freepool-runs/*/meta.yaml, codex rollouts
     (total_token_usage + per-turn used_percent).
   - Join ONLY by identifier present on both sides (e.g. glm run handle
     260907-212812-13581c3eb064-19f0 embeds the founder task id). NEVER nearest-timestamp or title
     matching — concurrent same-arm lanes make that misattribute and look plausible while wrong.
   - Unjoinable run -> usage_src=unjoined, COUNTED (never dropped).
   - Print: imported=<n> unjoined=<n> stores=claude:<n>,glm:<n>,freepool:<n>,codex:<n>
   - Idempotent: second run adds zero new records.

Acceptance: run importer against LIVE caches — imported+unjoined == run dirs walked. Second run:
zero new records.

Negative controls — MANDATORY, run each, show red, then revert and show green:
1. Inside the record-writing function BODY, drop attempt_id -> identity test goes RED.
2. Inside the importer's join function BODY, fall back to nearest-timestamp -> unjoined-honesty
   test goes RED (must assert the TALLY, not just row presence).
3. Inside the reader function BODY, return sums without n -> that test goes RED.
Mutations MUST be inside the function body, never top-level (a top-level insert fails every test
for the wrong reason and reads as a false pass — happened before, 2026-08-25).

Test files: plugins/leadv2/tests/test-arm-receipt-identity.sh,
plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh. Add EXTRA_SUITE_MAP rows in
plugins/leadv2/tests/run-all.sh so both are actually SELECTED — prove with --scope changed.

LANE_WRITES (touch ONLY these): plugins/leadv2/scripts/lib/leadv2-arm-receipts.sh,
plugins/leadv2/scripts/leadv2-arm-receipts-import.sh, plugins/leadv2/tests/test-arm-receipt-identity.sh,
plugins/leadv2/tests/test-arm-receipt-import-unjoined.sh, plugins/leadv2/tests/run-all.sh

Constraints: never git add -A (name paths explicitly); never reset --hard/clean/stash/worktree
prune; never push to origin; never print/log/commit any account id, email, token, or
claude-profiles.tsv content; never touch leadv2-dispatch-code.sh or lib/leadv2-route-arbiter.sh.

Report: what was built, negative-control red/green output for all three mutations, live importer
tally, second-run idempotency proof, exact git commit with its path list. Every claim needs its
artifact. Unverified -> say so explicitly.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-fb9df7f1" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.