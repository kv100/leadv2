# BEAT-LOOP-ORPHANS-01 — round 3: bring the lane onto main (merge conflict)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BEAT-LOOP-ORPHANS-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-pulse-watch.sh,plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh,plugins/leadv2/scripts/leadv2-backlog-pump.sh,plugins/leadv2/hooks/leadv2-single-lead-beat.sh,plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh,plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh,docs/handoff/BEAT-LOOP-ORPHANS-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `6eb6d56`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Why
Round 2 passed review (`review-gate.md: status: pass`). `git merge main` conflicts in
`leadv2-lane-pulse-watch.sh` and `leadv2-single-lead-beat-loop.sh` (main landed ONE-LANE-WATCH-01
and PLUGIN-PAPERCUTS-01 edits in the same regions; 125+/256- between the heads). The lead aborted
the merge; the tree is back at `6eb6d56`.

## Do
1. Restore any tracked files the suites dirtied (`git status` → `git checkout --` for
   `docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`), so the tree is clean.
2. `git merge main` (merge, not rebase). Resolve BOTH conflicts keeping both sides' intent: main's
   lane-watch/papercut changes AND this lane's session-kind gate (the `leadv2_hook_session_kind`
   call that makes a worker/unknown session exit 0 before arming any loop) plus the guarded
   owner-check. List every conflict hunk and its resolution in report.md.
3. On the merged tree run `bash plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh` (green) and
   `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh`
   (FALSIFIABLE); paste both. Then `tests/run-all.sh --scope changed`; paste the selected-suite lines.
4. Append "## Round 3 evidence" to report.md; commit the merge and the report; leave the tree
   clean. An uncommitted exit is a failed round.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-6d1452d6" "<question>" \
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