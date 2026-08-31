# PLUGIN-PAPERCUTS-01 — four small plugin defects, each measured today, each hitting every repo

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PLUGIN-PAPERCUTS-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/codex-task.sh,plugins/leadv2/config/leadv2-routing.yaml,plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh,plugins/leadv2/scripts/tests/test-plugin-papercuts.sh,tests/run-all.sh,docs/handoff/PLUGIN-PAPERCUTS-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

Four independent defects. All four are plugin-level, so all of them hit every adopted repo. Each
was measured on 2026-08-31 — do not re-derive, fix.

## [Critical] 1 — orphaned beat loops pulse from test fixture directories

```
$ pgrep -fa single-lead-beat-loop   (ppid / etime / cwd)
  3442   ppid=1  16:13     .../worktrees/LEAD-WORKER-CHANNEL-01
  5159   ppid=1  4:14:27   .../worktrees/LANE-FINISHED-IS-NOT-DEAD-01
 22083   ppid=1  22:41:43  .../worktrees/DISPATCH-PIN-CLUSTER-01
 64087   ppid=1  35:17     .../repo-glm        <- a TEST FIXTURE
 78581   ppid=1  3:21:28   .../repo-codex      <- a TEST FIXTURE
 77935   ppid=1  22:40:05  .../target          <- a TEST FIXTURE
```

Eleven of them, all reparented to launchd, several over 22 hours old, three running **inside test
fixture directories**. Killing them did not reduce the count — they respawn.

This is the most likely source of the founder's complaint that an unrelated repo's pulse appears in
his session: beats are being emitted from fixtures and from long-merged lane worktrees, by
processes nobody owns.

Two things: a beat loop must not survive the run that started it (find out why they are orphaned —
from the runtime, not by reading), and a suite must never leave one behind. Say in `report.md`
which of the two was the actual cause.

## [Critical] 2 — the codex arm names a tier its launcher rejects

`leadv2-routing.yaml:74` pins `tier: spark`; `codex-task.sh` accepts only `top|standard|volume`:

```
ERROR: spawn(codex) failed rc=1: [codex-task] unknown --tier: spark (expected top|standard|volume)
```

So the codex cell wins the auction and dies at spawn, silently falling through to a costlier arm.
Validate the configured tier against what the launcher accepts, and make a spawn-time fallthrough
to a costlier arm **log as a failure naming the arm and reason** — today it is indistinguishable
from a deliberate choice. Establish the correct current tier from the launcher, not from this
brief.

(If `CHEAP-ARMS-ARE-SWITCHED-OFF-01` has already landed this, verify and say so in `report.md`
rather than doing it twice.)

## [Medium] 3 — `--resume-lane` accepts only a bare name

Given an absolute path it concatenates and refuses:

```
lane_placement_refused reason=no_lane_worktree_for_ref
  looked_for=.../.claude/worktrees//Users/.../.claude/worktrees/ANTI-SILENCE-ONE-MECHANISM-01
```

Accept both a bare lane name and an absolute path to that lane's worktree, or reject the path form
with a message that shows the accepted shape. The current message shows a mangled path and no
guidance.

## [Medium] 4 — `task-add.sh` reports success and writes nothing

`scripts/task-add.sh "<intent>" --group X --acceptance-cmd '...' --expect '...'` printed JSON and
exited 0, and `grep` of `docs/tasks.yaml` afterwards found **zero** matching rows. A backlog writer
that silently drops rows is worse than one that errors: work was recorded nowhere and only survived
because it was also written to open-threads by hand.

Note this script lives in the **consuming repo**, not the plugin. Determine whether the defect is
in the script or in the plugin-side library it calls, fix it where it actually is, and say which in
`report.md`. If it is repo-local, still report it — do not silently skip it.

## Acceptance

Build `test-plugin-papercuts.sh` against fixtures — never real lanes, never the real backlog:

1. a run that starts a beat loop and then exits ⇒ no beat loop survives it;
2. a suite run ⇒ leaves no beat loop behind (regression guard for the fixture leak);
3. a routing cell whose tier the launcher rejects ⇒ loud validation error, not a fallthrough;
4. a spawn failure that falls through to a costlier arm ⇒ logged as a failure naming arm + reason;
5. `--resume-lane <bare-name>` ⇒ works (regression guard);
6. `--resume-lane <absolute path>` ⇒ works, or refuses with a message showing the accepted shape;
7. a backlog add that cannot persist ⇒ non-zero exit, never a success line.

Add the `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Pick one defect's fix as the declared negative control and name it in
  `report.md`.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never kill a process outside the fixture tree from a test.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

No beat loop outlives its run or its suite, an unknown tier fails loudly instead of falling through,
`--resume-lane` accepts or explains both argument shapes, a backlog write that does not persist
exits non-zero, and the declared mutation turns the suite red with the exit code following.
