# WATCHER-LIFECYCLE-LEAK-01 — beat/pulse watchers leak as PPID-1 duplicates

## Problem (measured live 2026-09-01, MacBook M1 Pro)
33 leadv2 processes with PPID 1; 17 of them are DUPLICATE copies of
`plugins/leadv2/scripts/leadv2-single-lead-beat-loop.sh` from ONE worktree
(etimes 2–38 min, so re-spawned every few minutes without killing predecessors).
`leadv2-lane-pulse-watch.sh` instances also persist at PPID 1 after their owner is gone.
Origin ticket: ~/Desktop/leadv2-laptop-load-ticket-for-dima-2026-09-01.md (follow-up #1).

## Goal — reduce process churn with ZERO behavior change to tasks/review/close
1. **Singleton per owner**: before spawning `leadv2-single-lead-beat-loop.sh` (and
   `leadv2-lane-pulse-watch.sh`), take a pidfile keyed by (session-id or lane-sig, repo).
   If the recorded pid is alive and its cmdline matches, DO NOT spawn a second copy.
   Stale pidfile (dead pid / wrong cmdline) → replace.
2. **Owner-bound self-reap**: each loop iteration checks its owning session is alive
   (owner pid via `kill -0`, or heartbeat-file mtime staleness > N intervals). Owner
   gone → the loop exits by itself within one interval. No loop may outlive its owner
   indefinitely at PPID 1.
3. **Reap on close**: the session/lane close path kills its own watchers (by pidfile),
   best-effort, idempotent.
4. **Instrumentation**: each spawn and self-reap appends one line
   (ts, script, owner, pid, event=spawn|dedup_refused|self_reap|reaped) to a small log
   so the ticket's acceptance (counts don't grow monotonically) is provable.

## Constraints
- Edit canonical plugin scripts only (this repo). No behavior change to beat cadence
  when exactly one healthy loop exists; the pulse must keep firing as today.
- Do not touch backlog pump, dispatch ladder, review/close semantics.
- Fail-open: if pidfile dir is unwritable, current behavior (spawn) is the fallback.

## Acceptance (tests required, run them)
- Unit/contract test: double-spawn of the beat loop with same owner → exactly 1 process,
  second exits with dedup_refused logged.
- Kill the owner pid → loop exits within one interval (test with short interval env).
- Negative control: revert the dedup check in a scratch copy → test goes red.
- `ps -axo pid,ppid,command | grep leadv2 | awk '$2==1'` count does not grow across
  a spawn/kill cycle repeated 3×.
