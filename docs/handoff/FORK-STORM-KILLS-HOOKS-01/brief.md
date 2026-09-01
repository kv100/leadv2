# FORK-STORM-KILLS-HOOKS-01 — a tool call costs 52 hook processes, and when fork() fails the HOOK dies, not the task

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FORK-STORM-KILLS-HOOKS-01`

LANE_WRITES: plugins/leadv2/hooks/hooks.json,plugins/leadv2/hooks/leadv2-hook-fork-budget.sh,plugins/leadv2/scripts/lib/leadv2-sleep.sh,plugins/leadv2/scripts/tests/test-hook-fork-budget.sh,plugins/leadv2/scripts/tests/test-no-orphan-sleep.sh,tests/run-all.sh,docs/handoff/FORK-STORM-KILLS-HOOKS-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The failure, as the founder hit it

Work stopped with `EAGAIN / fork: Resource temporarily unavailable`. The founder's own diagnosis:

> 56 orphaned `sleep` processes (PPID 1) — tails of monitors that had been killed. Plus 6 live
> claude sessions, Chrome, Steam. Every tool call forks several hooks; at the peak fork stops
> succeeding, and what fails is not the task — **it is the hook**.

Killing the orphans took the machine from 638 to 563 processes. Memory was fine (57% free) and the
limits were nowhere near (5333 procs, 1M descriptors) — so this was a spike, not a ceiling. He runs
3-4 repos at once, so the spike is routine, not exotic.

## Measured on this tree, 2026-09-01

```
hook commands per event:  PreToolUse 36   PostToolUse 16   SessionStart 13   Stop 7   ...
                          TOTAL 86 hook commands wired
```

**Every single tool call spawns 52 hook processes** (36 + 16), before any of them does its own work.
The heavy ones then fork 20-26 subshells / `python3` invocations internally:

```
leadv2-user-prompt-context.sh 26   leadv2-routing-guard.sh 26   leadv2-idle-lead-guard.sh 24
leadv2-promise-guard.sh 22        leadv2-merged-worktree-sweep.sh 22   leadv2-single-lead-beat.sh 21
```

So one tool call can cost several hundred forks. Multiply by 4 repos and the orphan backlog above,
and `fork()` failing is the expected outcome, not bad luck.

## [Critical] 1 — a hook must never take the task down with it

When a hook cannot fork, the tool call fails. That is backwards: every one of these hooks is
advisory or a guard, and none of them is worth losing the user's work over. Establish a single
fail-open entry discipline so a hook that cannot run degrades to "did not run" instead of failing
the call — and make the degradation *visible* (a counter or a journal line), never silent, or we
trade a loud failure for a quiet one.

Determine from the runtime what the harness actually does with a hook that dies on EAGAIN, and say
so in `report.md`. Do not assume — the fix depends on it.

## [Critical] 2 — kill the orphan-`sleep` class at the source

Orphans appear because a watcher is killed while its `sleep` child is running: the child is
reparented to launchd and survives forever. This has already cost us twice today — 47 orphaned
`sleep 900` processes held a machine-wide `flock` so every lane blocked, and an orphaned
`codex-task.sh __quota-watch` kept a finished lane reading as "live" for 33 minutes.

Two things to fix, and the second is the real one:

- a watcher must reap its own children on exit (trap + kill the process group, not just the pid);
- **`sleep` should not be a process at all in a poll loop.** Bash can wait without forking. Provide
  one helper (`leadv2-sleep.sh` or equivalent) that every poll loop uses, and convert the loops that
  today spawn a bare `sleep`. A wait that forks nothing cannot leave an orphan, and it also removes
  its share of the fork pressure in §3.

Census first: list every poll loop in the plugin that spawns `sleep`, and say in `report.md` how
many you converted and which you could not, with the reason.

## [Critical] 3 — 52 hooks per tool call is the pressure; cut it

Most of those 36 PreToolUse hooks do not care about most tools — a guard for `Edit` runs on every
`Bash`, forks, reads its input, decides it is irrelevant, and exits. The harness supports matchers;
use them so a hook only forks for the tools it can act on.

Requirements:

- **no behaviour change**: a hook that fires today for a given (event, tool) must still fire. This
  is a pure cost reduction, and any narrowing must be justified per hook in `report.md`;
- report the before/after count of hook processes for a representative `Bash` call and for an `Edit`
  call — that number is the deliverable;
- do not reorder the hook arrays. Order is load-bearing and the founder has said so explicitly.

## [Medium] 4 — a fork budget the machine can see

Provide a way to answer "are we near the fork wall right now" without the founder diagnosing it by
hand: current process count, our share of it, orphan count. One command, cheap enough to run from a
session start without adding to the problem it measures.

## Acceptance

Fixture-based suites — never kill a process outside the fixture tree, never touch a real session:

1. a watcher killed mid-sleep ⇒ no `sleep` survives it (this is the founder's 56-orphan case);
2. a watcher exiting normally ⇒ no child survives (regression guard);
3. the converted poll loop still wakes on time and still terminates on its stop condition;
4. a hook that cannot fork ⇒ the tool call still succeeds, and the degradation is recorded;
5. a `Bash` tool call ⇒ strictly fewer hook processes than before, with the count asserted;
6. every (event, tool) pair that fires today still fires after the matcher narrowing — assert this
   against the hook table, not by spot-checking two hooks;
7. the fork-budget command reports counts and exits 0 on a healthy machine.

Add the `EXTRA_SUITE_MAP` rows and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Removing the orphan reaping must turn suite 1 red.
- A kill counts only if the suite alone goes red, and only if it was green first.
- Never kill a process outside the fixture tree. Never reorder a hook array.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

A killed watcher leaves no `sleep` behind, a hook that cannot fork loses only itself and says so, a
tool call costs measurably fewer hook processes with no hook losing its trigger, and the founder can
see how close the machine is to the wall with one command.
