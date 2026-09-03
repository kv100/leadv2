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
