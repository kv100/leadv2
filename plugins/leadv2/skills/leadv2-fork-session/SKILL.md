---
name: leadv2-fork-session
description: "Lead-side pre/post ops for a fork-owned /leadv2 session: isolated worktree lifecycle (preflight/postflight), a bounded async Gate-1 (ask), and lane-scoped commits. Triggers: dispatching or reaping a fork-run session."
allowed-tools:
  - Bash
---

# leadv2-fork-session.sh — running a full /leadv2 session in a fork

FORK-RUNS-A-SESSION-01: a fork used to be limited to fragments (a review, a
judgement, a synthesis) because three phases looked lead-only — Gate 1 needs
founder input, Phase 6 needs `ExitWorktree`, Phase 8 reaps the worktree. All
three already have bash answers for headless lanes, and this script is the
thin lead-side wrapper around them. It never enters a tool worktree itself
and never reimplements a gate — it shares the session's cwd with the lead and
never `cd`s.

Source of truth: the script's own header comment
(`plugins/leadv2/scripts/leadv2-fork-session.sh`). This file is the "when do
I reach for this" summary; if the two disagree, the script wins.

## When

- Before spawning a fork to run a `/leadv2` session end to end: call
  `preflight` first, from the LEAD, to create the isolated lane.
- Inside the fork, whenever Gate 1 needs founder input: call `ask` instead
  of blocking on the interactive prompt.
- Inside the fork, at Phase 6, to commit into the lane (never a bare `git
  commit` on the shared session cwd).
- After the fork reports done (or dies), from the LEAD: call `postflight`
  to reap the lane.

## Ops

```
leadv2-fork-session.sh preflight <task-id> [class]
```
Ensures an isolated worktree lane (`leadv2-lane-worktree.sh ensure`),
registers it in `active.yaml`, writes `<lane>/docs/handoff/<task-id>/fork-lane.env`
(TASK_ID/LANE_ROOT/CONTROL_PLANE), and prints the lane's absolute root —
**one line, nothing else.** Idempotent: re-running returns the same lane.
Refuses (exit 1) whenever the lane isn't genuinely isolated — kill-switch
`LEADV2_LANE_WORKTREE=off`, a resurrection-refused fallback to the shared
root, or a lane whose branch has drifted off `worktree-<task-id>`. A fork
sharing the lead's checkout is the exact 2026-07-28 mutual-clobber shape;
preflight fails loud rather than degrading.

```
leadv2-fork-session.sh ask <task-id> "<question>" --option "label|desc" [--option ...]
    [--default-option <label>] [--phase <p>] [--timeout-poll <sec=540>]
```
Fork-side Gate 1. Writes the question to the control-plane `questions/` dir
(the founder answers via `/leadv2 reply`, same surface as every lane), then
polls bounded so the call stays under the tool's timeout ceiling.
- `exit 0` — answered; the chosen option's label is on stdout.
- `exit 3` — still pending after the poll cap. **Not a failure** — re-invoke
  the fork with the SAME question text/options/phase later; it resumes
  polling the SAME question (identity survives via a fingerprint), it does
  not ask a duplicate.
- `exit 1` — usage error, or a DIFFERENT question is already pending for
  this task. Answer that one first, or withdraw it:
```
leadv2-fork-session.sh ask <task-id> --cancel-pending
```

```
leadv2-fork-session.sh commit <task-id> -m "<msg>" (--all | --paths <p> ...)
```
Phase 6 commit **into the lane** — every git call carries `-C <lane-root>`,
never a bare `git` on the shared session cwd. Re-runs the isolation
assertion (the same predicate that gates `preflight`). Empty index is a
no-op (`exit 0`) so a retry is safe.

```
leadv2-fork-session.sh postflight <task-id> [--self-spawn] [--force]
```
Reaps the lane once the fork is done. Refuses (leaves the worktree on disk
for inspection) when the lane has uncommitted/untracked changes, or when its
branch carries commits not yet reachable from main — `--force` overrides
both. No-op-safe when no worktree exists for the task. `--self-spawn` (or
`LEADV2_DAEMON=1`) additionally spawns the next session, **lead-only**,
strictly before the reap.

## Coverage

`tests/test-fork-session-guard.sh` (preflight + isolation checks),
`tests/test-fork-liveness-verdict.sh` (postflight), `tests/test-gate1-async-route.sh`
(ask). Each carries at least one mutation control proven RED then GREEN, not
assumed from "mutation applied".
