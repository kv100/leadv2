# PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01 — round 7: stop lying green, then finish the pid

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-active-registry.sh,plugins/leadv2/scripts/leadv2-broad-status.sh,plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh,tests/run-all.sh,docs/handoff/PULSE-BOARD-EMPTY-WHILE-LANES-LIVE-01/

HEAD is `7d7d5f5`. Main is `3df9d90`. Round 6's ephemeral consolidation lands and stays —
do not redo it.

I ran your suite myself:

```
[LANE-REGISTRY-OUTLIVES-DISPATCHER-01] passed=4 failed=5
rc=0
```

## [Critical] the suite exits 0 with five failing assertions

This is the exact disease the lane exists to kill, inside the lane's own suite. CI selects
this file; with `rc=0` it reads five red assertions as a pass. Make the exit code carry the
result: non-zero whenever `failed>0`, and prove it — force one assertion to fail, show
`echo $?` printing non-zero; restore, show 0.

## [Critical] `_lv2_durable_pid` records an ancestor, not the watcher

```
FAIL: registry pid is not the controlled watcher pid (row=47081 watcher=none)
```

`_lv2_durable_pid` (`leadv2-active-registry.sh:669`) walks the `$PPID` chain to the nearest
long-lived ancestor. Under a test harness that ancestor is the harness, so the recorded pid
never belongs to the watcher and liveness can never be falsified — a lane's death is
undetectable and, symmetrically, a live lane gets declared dead. Five false deaths tonight,
all on a lane that was actively writing files.

Record the pid of the process that actually owns the lane. If the durable-pid walk exists for
a real reason, keep it but stop it at the first ancestor that is not part of the invoking
harness, and make the suite assert the recorded pid `kill -0`s to the watcher it started.

## [Critical] durable own-repo registry drops the ephemeral lane

```
FAIL: durable own-repo registry dropped ephemeral lane (invalid)
```

Consolidation renders on the board but the durable root loses the row, so the lane vanishes
from the registry the next reader consults.

## Rules

- Mutation INSIDE the production function body, RED, revert, GREEN, clean `git diff --stat`.
  A suite that stays green with the fix removed is a failed control; a printed `RED control:`
  line that does not change the exit code is not an assertion — and neither is a `FAIL:` line
  that leaves `$?` at 0.
- No `grep` against script source as an assertion; no negated command as an assertion; no
  scratch-copy mutation; no `git show HEAD:` pre-image; a commit message is not evidence.
- Bash 3.2.57 only; every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

`passed=N failed=0` with a non-zero exit proven on a forced failure, all three items above
closed, and a clean `git diff --stat`. Then this lane is merge-ready.
