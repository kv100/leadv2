# V3-DISPATCHER-ACCEPTANCE-FIX3-01 — close the codex blockers (~/Projects/leadv2)

Lane worktree b4042501: checkpoint 029ce01 + UNCOMMITTED fix2 edits (guard vs --resume-lane —
test-lane-placement-pin and test-status-surface-fast-names are now solo-green; do NOT undo
them). FIRST: commit the current working-tree state as a wip checkpoint before your own edits.

Codex adversarial review found 4 issues — READ THE REPORT:
docs/handoff/dispatch-b4042501-review/codex.r2.md
1. BLOCKER: the foreign-root guard's selection/refusal is not written to the task journal —
   add the journal line (respect JOURNAL_TASK so it lands in the task journal, not stderr).
2. HIGH: `retry-dead` reports success even when the ledger-row removal failed — make rc honest
   (verify the row is gone; non-zero + loud line on failure).
3. MEDIUM: the retry test is non-hermetic under the default-on guard and doesn't prove journal
   delivery — fix the test (hermetic fixture root + assert the journal line lands in the task
   journal file).
4. MEDIUM: an env root that is a PARENT/inside-path of the real repo root still rejects a
   legitimate explicit pin — normalize+compare by realpath containment, not string equality;
   add the edge-case leg.

FOREGROUND solo: test-dispatch-retry-dead.sh, test-foreign-project-root-guard.sh,
test-lane-placement-pin.sh, then full run-core-offline — all green. NOTE: full-suite false
reds from PARALLEL runs plague this repo; run suites strictly solo (no backgrounding) and if a
suite fails, rerun it solo once before treating it as your regression. COMMIT everything on
the lane branch (uncommitted exit = incident).

## Off_limits
leadv2-dispatch-product-close.sh; routing order/ceilings; supervise*.

## Terminal artifact
Commit shas (checkpoint + fix3) + raw green output for the 3 suites + core-offline summary +
DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-1e7c811d" "<question>" \
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