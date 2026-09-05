# RESUME-LANE-ACCEPTS-PATH-01 — round 5: bring the lane onto main (merge conflict)

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RESUME-LANE-ACCEPTS-PATH-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh,docs/handoff/RESUME-LANE-ACCEPTS-PATH-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `00a4141`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Why
Round 4 passed review (`review-gate.md: status: pass`), but the lane branch is 102 commits behind
main and `plugins/leadv2/scripts/leadv2-dispatch-code.sh` conflicts (main gained PLUGIN-PAPERCUTS-01
and ONE-LANE-WATCH-01 edits in the same regions: 117+/135- between the two heads). ff-only landing
is impossible until the lane contains main.

## Do
1. First restore any tracked files the test suites dirtied (`git status`; fixture dirs
   `docs/handoff/dispatch-nw*` and `docs/LEAD_V2_STATE.md` → `git checkout --`), so the tree is clean.
2. `git merge main` (merge, not rebase — keep the reviewed commits' hashes). Resolve the conflict in
   `leadv2-dispatch-code.sh` keeping BOTH sides' intent: main's papercut/lane-watch changes AND this
   lane's `_lv2_is_lane_worktree_path` path-equality check + cwd-root fallback. No hunk from either
   side may be dropped silently — list every conflict hunk and how it was resolved in report.md.
3. Run `bash plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh` (green, under 40 s) and
   `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh`
   (FALSIFIABLE) on the merged tree; paste both. Then `tests/run-all.sh --scope changed` and paste
   the selected-suite lines.
4. Append "## Round 5 evidence" to report.md; commit the merge and the report. Leave the tree
   clean (`git status` empty apart from untracked run artifacts). An uncommitted exit is a failed
   round.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-a31224e7" "<question>" \
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