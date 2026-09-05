# COMBO1-FIX2 — close 3 codex findings on SCOPE-DISCIPLINE (~/Projects/leadv2, lane 201b3f97)

Lane is 57/0 green; codex review FAIL with 3 findings — READ THE FULL REPORT FIRST (exact
anchors + repro + fix directions): docs/handoff/dispatch-201b3f97-review/codex.r1.md
(check the worktree copy .claude/worktrees/201b3f97/docs/handoff/... if the root one is
missing).

1. HIGH: the scope gate only inspects added/modified paths — DELETIONS and RENAME SOURCES
   outside the write-set pass silently. Parse the diff for D and R (both sides of the
   rename) and bounce those too.
2. MEDIUM: kill-switch (scope gate off) does not restore prior behavior byte-for-byte —
   diff the gated-off output against pre-feature output and make them identical.
3. MEDIUM: the 4 new scope tests are green-first (not red-first) and the bypass path is
   untested — rebuild them on the harness idiom (pre-fix baseline leg must FAIL), add a
   bypass-path leg.

FOREGROUND everything, suites strictly SOLO, COMMIT before ending.

## Acceptance
Red legs shown failing against baseline · test-builder-selfcheck-gate.sh green ·
full run-core-offline FOREGROUND SOLO green · bash -n + shellcheck -S warning · COMMIT.

## Off_limits
leadv2-dispatch-code.sh, leadv2-review-run.sh (combo-2 lane owns them); routing; supervise*.

## Terminal artifact
Commit sha + per-finding red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a0b0fe5a" "<question>" \
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