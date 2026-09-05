# V3-STOP-GATE-FIX2-01 — the Hole-2 fix regressed healthy worker completion (~/Projects/leadv2)

Lane worktree HEAD 747f453 + your predecessor's UNCOMMITTED edits to
leadv2-dispatch-product-close.sh + test-stop-gate.sh (closing critic holes 1-2 — report:
docs/handoff/dispatch-e93d9162-review/critic.full.md). Those edits are red:
`tests/test-no-work-terminal.sh` solo FOREGROUND run = 35 passed / 8 FAILED:

- diff-writing worker exits through non-empty path (got '5' want '0')
- exit-time review.diff is empty
- diff-writing worker misclassified no_work
- diff-writing worker terminal row is not landed
- codex liveness probe called only 2 times
- Sonnet natural completion reaches non-empty close path (got '5' want '0')
- Sonnet natural-completion diff missing
- revive_blocked_by_gate waited to timeout instead of finalizing original handle

Pattern: HEALTHY diff-writing completions now take the exit-5 (worker_timeout) path and/or the
exit-time diff is emptied. Suspects: (a) the stop-gate call added before `exit 5` in the reap
branches changed control flow or return codes so natural completions fall into the timeout
branch; (b) the auto-commit itself commits the work BEFORE review.diff is computed, so the
exit-time diff (worktree-vs-base uncommitted diff?) reads empty — check how review.diff is
produced and make the diff computation see committed lane work (diff vs main, not vs index),
or order the gate after diff capture.

Work: read the current uncommitted diff (`git diff` in the lane), root-cause against
test-no-work-terminal.sh's fixtures, fix, then FOREGROUND solo:
1. tests/test-no-work-terminal.sh — must be 43/0.
2. tests/test-stop-gate.sh — all legs incl. the new (d)/(f) stay green.
3. tests/test-lane-diff-single-repo.sh — was also red at the gate; if it still fails solo,
   check whether the failure is your diff or the tripwire noise (~/.claude/leadv2-state writes
   from other sessions) and say which with evidence.
4. plugins/leadv2/scripts/tests/run-core-offline.sh full FOREGROUND solo green.
COMMIT everything on the lane branch (uncommitted exit = incident).

## Off_limits
leadv2-dispatch-code.sh routing block; supervise*; builder-selfcheck internals.

## Terminal artifact
Commit sha + 43/0 raw output + core-offline summary line + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6f719827" "<question>" \
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