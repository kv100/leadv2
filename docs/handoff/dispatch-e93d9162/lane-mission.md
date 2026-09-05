# V3-STOP-GATE-01 — commit-before-exit enforcement (plugin repo ~/Projects/leadv2)

Disease (live, 2026-08-19/20): 6+ worker exits left real work UNCOMMITTED in the lane
worktree — the lead had to checkpoint-commit by hand every time (SUPDEL 47 files, V3-GLM 24,
ENV-GUARDS 6, T2 twice). An uncommitted exit is invisible to every downstream phase and one
parallel session away from being clobbered.

## Work
1. In leadv2-dispatch-product-close.sh, at the point the worker's exit is detected (the
   kill -0 wait loop region) and BEFORE the review/e2e phases: if the lane worktree has
   tracked modifications or untracked files INSIDE the declared write-set, auto-commit them
   on the lane branch as `wip(<task>): auto-checkpoint on worker exit (STOP-GATE)` and
   journal `stop_gate_autocommit task=<sig> files=<n>`. Junk outside the write-set is NOT
   committed (that is what unscoped_lane_work already handles).
2. Worker-protocol text (the mission preamble in leadv2-dispatch-code.sh, same guarded
   pattern as the selfcheck paragraph): one paragraph — "commit your work on the lane branch
   before ending your session; an uncommitted exit is treated as an incident".
3. Kill-switch env LEADV2_STOP_GATE=0 restores today byte-for-byte (same idiom as
   LEADV2_BUILDER_SELFCHECK).
4. Red-first suite tests/test-stop-gate.sh: (a) worker exits with uncommitted write-set
   files → auto-commit happens, journal line present, review phase sees a committed tree;
   (b) junk outside write-set NOT committed; (c) flag=0 → no behavior change. Register in
   run-core-offline.sh.

## Acceptance
Own suite green (red-first legs shown) · run-core-offline FOREGROUND solo green in the lane
(never background-and-idle-wait — that kills workers) · bash -n + shellcheck -S warning ·
COMMIT on lane branch.

## Off_limits
Routing block of leadv2-dispatch-code.sh (only the mission-preamble region); supervise*;
lib/leadv2-builder-selfcheck.sh internals.

## Terminal artifact
Commit sha + raw probe outputs + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e93d9162" "<question>" \
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