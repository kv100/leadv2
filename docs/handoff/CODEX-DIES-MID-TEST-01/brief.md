# CODEX-DIES-MID-TEST-01 — the codex arm produces nothing on lanes whose work needs a long test run

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-DIES-MID-TEST-01`

LANE_WRITES: plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/scripts/leadv2-codex-session-runner.sh,plugins/leadv2/scripts/tests/test-codex-longrun.sh,tests/run-all.sh,docs/handoff/CODEX-DIES-MID-TEST-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured, 2026-09-01

Four codex dispatches across two lanes, several hours of wall clock, **zero commits beyond the lane
anchor**:

```
TESTS-POLLUTE-REAL-JOURNAL-01   commits beyond anchor: 0    silent 142m
MAIN-CORE-SUITE-RED-01          commits beyond anchor: 0    silent 31m (after re-dispatch)
PHASE-GATE-IS-INVERTED-01       died once mid-run; salvaged 149 lines by hand
```

Every job log ends the same way — the last line is the START of a test command, with no completion
line, no error, and no exit status:

```
[2026-09-01T13:33:16Z] Running command: ... 'LEADV2_SUITE_LOCK_DISABLE=1 timeout 120 bash .../test-...
   <log ends>
[2026-09-01T14:33:53Z] Running command: ... 'LEADV2_SUITE_LOCK_DISABLE=1 timeout 120 bash .../test-...
   <log ends>
[2026-09-01T14:34:59Z] Running command: ... lv2guard.sh -c 'LEADV2_SUITE_LOCK_DISABLE=1 time...
   <log ends>
```

`codex-task.sh status` then reports `failed`. The reaper's `CODEX_RUNNING_DEAD_KILL_MIN` branch only
records a corpse it can prove — it is the observer here, not the cause: the worker pid is already
gone.

By contrast the GLM lanes on the same machine, in the same hour, committed repeatedly
(`PLUGIN-PAPERCUTS-01` 4 commits, `FORK-STORM-KILLS-HOOKS-01` 4 commits, both merged).

## [Critical] 1 — find why the process dies, from the runtime

Do not theorise. Reproduce: dispatch a codex job whose mission runs a test taking several minutes,
and capture what kills it — a wall-clock cap, an idle/no-output cap, an OOM, a parent exiting and
taking the group, a harness-side session limit. Name the killer in `report.md` with the evidence
that identifies it. Everything else in this brief depends on that answer.

Two candidate directions, neither assumed:

- the job is killed for producing no OUTPUT while a long test runs — the same idle-detector shape
  that `glm-coder.sh` logs as `STDOUT_IDLE idle_s=1200 ... observation only`;
- the job is killed on total runtime regardless of activity.

The distinction matters: the first is fixed by heartbeating during long children, the second by
raising or removing a cap.

## [Critical] 2 — a killed job must say so

Today the job log simply stops. No line records that the worker was killed, by what, or when. That
is why this took four dispatches to notice — each looked like a lane that "was still working".
Whatever kills a job must write a terminal line naming itself and the reason, and that line must
reach the dispatch journal so lane liveness sees it.

## [Critical] 3 — the arm must degrade, not vanish

While this is broken, a codex lane silently yields nothing. The router keeps choosing codex because
nothing tells it the arm is failing. **Do NOT fix this by excluding codex from routing** — the
founder's standing rule is that quota, task shape and complexity decide the arm, never a hardcoded
list. Fix it so a failed job is *recorded as a failure the router can see*, and let the ladder do
its job.

## Acceptance

1. a codex job whose child runs longer than the suspected cap ⇒ completes, or is killed with a
   terminal line naming the killer and reason;
2. that terminal line reaches the dispatch journal, so lane liveness reports the lane dead rather
   than silent;
3. a killed codex job ⇒ recorded as an arm failure the router consumes on the next resolve;
4. no arm is excluded by name anywhere in the change;
5. a GLM dispatch is unaffected (regression guard).

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- Measure a suite's exit code WITHOUT a pipeline: `cmd > log 2>&1; echo $?`.
- No `grep` against script source as an assertion; a printed `FAIL:` line that leaves `$?` at 0 is
  not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.

## Done means

A codex lane either finishes its work or dies loudly with a named cause that the router and the
liveness view both see — never again four dispatches of silence that look like progress.
