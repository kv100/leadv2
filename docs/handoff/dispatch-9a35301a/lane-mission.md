# MERGE-QUEUE-DEAD-HEAD-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MERGE-QUEUE-DEAD-HEAD-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-merge-queue.sh,plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh,tests/run-all.sh,docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `e70fc73`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`). Write `report.md` under
`docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/` (round 1 had none) and `git add -f` it — the handoff dir
is gitignored. An uncommitted exit is a failed round.

## Review verdict on round 1 (reviewer glm) — FAIL, high=1
- **`leadv2-merge-queue.sh:177`** — the dead-enqueued reclaim evicts the CALLER's own row too:
  when a task re-runs `acquire` after a crash (the re-dispatch path), its earlier `enqueued` entry
  is reclaimed as dead, the new call never re-enqueues, waits for the full lock (`TIMEOUT`, default
  1800 s) and exits 2. The reviewer reproduced it.

## Do
1. Reclaim must never touch a row whose `task_id` equals the caller's; instead the caller's stale
   row is REPLACED (new pid, new ts) in place, keeping its queue position, with a
   `re-enqueued` ledger event. Rows of OTHER dead tasks are reclaimed as in round 1.
2. Add the reviewer's reproduction as a suite case: task A enqueued with a dead pid → task A
   calls `acquire` again → gets ACQUIRED (or its turn) within 5 s, never TIMEOUT; ledger shows
   `re-enqueued` for A, no `dead-enqueued` for A.
3. Mutation negative control, RUN and paste red: drop the same-task exemption → the new case red.
   Revert.
4. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-merge-queue-dead-head.sh`
   → paste FALSIFIABLE; `tests/run-all.sh --scope changed` → paste the selected-suite line.
5. "## Round 2 evidence" in report.md; commit.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-9a35301a" "<question>" \
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