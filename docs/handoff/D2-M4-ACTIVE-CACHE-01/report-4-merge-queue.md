# D2-M4 (4th real conversion) — leadv2-merge-queue.sh

## Change

`pid_alive()` caught bare `except (OSError, ValueError)` — `PermissionError`
subclasses `OSError`, so EPERM (pid exists, owned by another user, e.g.
reparented to ppid=1) collapsed into the same "dead" branch as ESRCH
(D2 brief #9/#14). `pid_alive()` gates all three reclaim sites in the file
(`:213` dead-enqueued head, `:232` dead holder, `:269` dead re-enqueue
target) — a stale-but-EPERM row would get reclaimed (its merge-queue slot
stolen) out from under a still-running process.

Split: `ProcessLookupError` → dead (unchanged), `PermissionError` → alive
(new). `int(pid)` conversion moved to its own try so a `None`/non-numeric
pid still degrades to "dead" via `TypeError`/`ValueError`, same as before.

Not converted via `leadv2-lane-liveness.sh --all --json` — this registry is
the merge-queue's own JSONL event log (`enqueued`/`acquired`/`released`
events keyed by task_id + pid), not `docs/leadv2/active.yaml`. Same bug
class, different registry — a local except-clause fix is the correct,
minimal repair here, same reasoning as the `leadv2-lane-heartbeat.sh`
conversion.

## New test

`test-merge-queue-dead-head.sh` case (e): a stale enqueued head with pid=1
(guaranteed EPERM for a non-root caller, guaranteed to exist) must NOT be
reclaimed — `status` stays clean (no `DEAD-ENQUEUED`), no `dead-enqueued`
ledger entry. 11/11 pass (9 pre-existing + 2 new assertions).

## Mandatory negative control (mutation-control-proven)

Mutated line 159 (`except PermissionError: return True` → `return False`,
reverting to the pre-fix collapse). Suite goes RED exactly on case (e):
`FAIL - case (e): EPERM head wrongly marked DEAD-ENQUEUED`. GREEN on the
committed code.

## Commit

`5110d0b9`.

## Running tally (real M4 list, denominator still shrinking as false
positives surface — see prior reports for the full misclassification log)

Converted: `leadv2-active-cache.sh`, `hooks/leadv2-worktree-enforce.sh`,
`leadv2-lane-heartbeat.sh`, `leadv2-merge-queue.sh` (this report).
Misclassified/out-of-scope (7): `leadv2-pulse-beat.sh`,
`hooks/leadv2-orphan-monitor-sweep.sh`, `hooks/leadv2-stale-pid-sweep.sh`,
`leadv2-fanout-lane-launcher.sh`, `leadv2-helpers.sh` (4 sites, all out),
`leadv2-lane-pulse-watch.sh`, `leadv2-lane-status-line.sh`.
Deferred (separate rows, per Leadmain): `leadv2-fanout.sh` (mixed),
`leadv2-lane-state.sh`/`lane_reconcile` (Leadmain's own row, wide blast
radius), `leadv2-active-registry.sh` (×4 sites, latent, sequencing TBD).
Remaining to check: `hooks/leadv2-task-anchor.sh` (1066 lines, own pass),
`leadv2-provider-canary.sh`, `leadv2-status-collector.sh`,
`lib/leadv2-worktree-protected.sh`, `codex-guard.sh`, `leadv2-codex-lead.sh`
(last two flagged borderline by the brief itself).
