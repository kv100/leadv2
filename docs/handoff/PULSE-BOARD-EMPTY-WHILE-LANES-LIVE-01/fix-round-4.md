# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 4: the fix is deployed and the board is still empty

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/leadv2-status-collector.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-pulse-empty-board.sh,plugins/leadv2/scripts/tests/test-collector-sees-registered-lane.sh,plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh,plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

**YOU are the developer on this lane. This brief is YOUR work order, not a status report about
someone else's in-flight job.** A previous attempt read this file, concluded the work was "already
running" elsewhere, wrote nothing and exited. There is no other agent on this task. Open the lane
worktree below, make the changes, run the suites, commit.

Full report: `docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/review-r3.md`. HEAD is `c2dfd0d`.

**Round 3 was right about everything it claimed and the reviewer confirmed each — keep it all.**
The root cause is real and evidenced: `~/.claude/settings.json:19` ships
`LEADV2_LANES_ALL_REPOS: "0"`, mtime 27 Aug, confirmed live. The collector now pins `=1` at
`leadv2-status-collector.sh:125`. Suites 8/0, 4/0, 16/0; `</dev/null` in place; artifacts are honest
RED/GREEN pairs.

**The lane is merged to `~/Projects/leadv2` main as `7c78c7a`, and the plugin cache carries the pin
too — I checked both copies.** So round 3's fix is live.

## [Critical] the board is STILL empty with the fix deployed — ALL_REPOS was necessary, not sufficient

At beat `2026-08-30T19:54:39Z`, fix live in canonical AND cache, the board rendered only three
completed codex reviews and no lanes — while five lanes were writing files.

The reason is not the collector. The lane registry is empty:

```
~/.claude/leadv2-state/leadv2/active.yaml           -> no rows at all
~/.claude/leadv2-state/persona-engine/active.yaml   -> one row:
    - at: '2026-08-30T15:58:40Z'
      event: registered
    - at: '2026-08-30T15:58:40Z'
      event: deregistered
      detail: dispatcher_exit
```

Registered and deregistered in the **same second**, cause `dispatcher_exit`. The dispatcher spawns
the worker and exits; its exit trap deregisters the lane — while the worker runs on for another
hour. So every lane is unregistered during the whole time it does its work, and a board reading the
registry can only ever render an empty table.

That is the founding defect's real mechanism at the layer the founder reads.

- A lane's registry entry must outlive the dispatcher process that created it. Deregistration
  belongs to the worker's terminal, not the dispatcher's exit trap.
- Then re-render and paste a board listing the live lanes, including at least one whose worktree is
  in the OTHER repo — own-repo lanes rendered fine even before round 3, so only a foreign row also
  proves the ALL_REPOS fix.

Add `tests/test-lane-registry-outlives-dispatcher.sh`: spawn a lane, let the dispatcher exit, assert
the registry still lists it. Mutation-prove it by restoring the exit-trap deregistration and showing
RED.

## [High] the liveness prober calls a writing lane dead

Outstanding from round 3 (the brief allowed a fix or a written-up finding; neither happened). Today
it asked to escalate `SESSIONSTART-HOOKS-DISCARDED-01` as `corroborated dead: pid dead` five times
while that lane was writing dozens of files.

It also compounds: a dispatch refused with `lane_is_live` still registers an arm row, so the next
retry sees the lane as live and is refused too — three chained refusals today on a lane whose stream
had been stale for an hour. Liveness must come from stream or worktree write freshness, not from a
pid a re-dispatch replaced or a row a refusal wrote. Fix it here if it is in this write set,
otherwise write the file:line to
`docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/liveness-prober-false-dead.md` and say so in
`report.md`.

## [Low] keep round-4 artifacts in the lane

Round 3's brief never reached the lane's own `docs/handoff/`, so the reviewer could not read it.
This file is there. Commit round-4 artifacts beside it with `git add -f <file>`.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the function body of the production file, RED,
  revert, GREEN. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- Run every suite in the write set to completion before committing and paste the runs.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

A pasted board render listing the live lanes with at least one foreign-repo row; a registry entry
that survives the dispatcher's exit, held by a mutation-proven suite; and the liveness prober either
fixed or written up with file:line.
