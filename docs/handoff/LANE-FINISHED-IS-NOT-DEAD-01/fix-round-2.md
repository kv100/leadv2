# LANE-FINISHED-IS-NOT-DEAD-01 — round 2: your suite is green without your fix

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LANE-LIVENESS-THREE-STATES-02`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-liveness.sh,plugins/leadv2/scripts/leadv2-lanes-snapshot.sh,plugins/leadv2/scripts/tests/test-lane-finished-state.sh,tests/run-all.sh,docs/handoff/LANE-FINISHED-IS-NOT-DEAD-01/

Rebase onto current main first — three lanes landed after your branch point.

Your work is committed and preserved (`1c7094f`) — the lane was killed by the machine-wide suite
lock before it could commit, and I salvaged it. Round 1 is not being discarded.

## The measurement

```
$ bash plugins/leadv2/scripts/tests/test-lane-finished-state.sh
[TEST] RESULTS: 6 passed, 0 failed

$ git checkout main -- plugins/leadv2/scripts/leadv2-lane-liveness.sh \
                       plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
$ bash plugins/leadv2/scripts/tests/test-lane-finished-state.sh
[TEST] RESULTS: 6 passed, 0 failed        <-- rc=0, STILL GREEN
```

Six assertions, none of which can tell the two-state code from the three-state code. The suite
proves nothing about either.

## Why this one matters more than most

This defect cost real work today, twice, and I have the evidence:

- I reported six lanes as "in работе" to the founder. All six were dead — no worker process,
  anchor-only commits, 3-6 hours stale. The liveness surface said otherwise and I believed it.
- `--resume-lane` refused a restart with `lane_is_live verdict=starting:70` for a lane with **zero**
  live workers, because a previous failed attempt had registered it as starting and nothing ever
  aged that out. The false-live verdict blocked the recovery of a lane that was genuinely dead.

So the three states are not a nicety. `dead` and `finished` and `live` are three different
decisions, and today the code cannot make any of them reliably.

## The bar for round 2

1. **Revert both production files to main ⇒ the suite goes RED**, exit code following. Show the
   run. Nothing else counts until this holds.
2. Restore ⇒ green. Show that run.
3. `git diff --stat` clean afterwards.
4. Say in `report.md` which of the six assertions touched production code and which were vacuous.

## Cases the suite must actually distinguish — from today's live failures, not invented

- no worker process + a commit newer than the lane anchor ⇒ **finished**, never `dead`;
- no worker process + only the anchor commit ⇒ **dead**;
- a registration in `starting` with **no live pid**, older than its own grace ⇒ **dead**, and
  `--resume-lane` must admit it. Today it says `lane_is_live` forever;
- a live pid whose cwd is the lane worktree ⇒ **live**, regardless of stream mtime;
- a lane whose only "activity" is a leaked `leadv2-single-lead-beat-loop.sh` with `ppid=1` ⇒
  **not live**. There were 11 such orphans on this machine today, some 22 hours old, several inside
  test fixture directories.

Liveness must be decided by a live process whose cwd is that lane, not by a status field. A status
field is intent, not fact.

## Rules

- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- Never read or write the real lane registry; fixtures only.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Run with `LEADV2_SUITE_LOCK_DISABLE=1` — the machine-wide suite lock is what killed round 1.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Reverting the fix turns this suite red, a lane with no pid and a real commit reads `finished`, a
stale `starting` registration with no pid reads `dead` and can be resumed, and the report names
which round-1 assertions were vacuous.
