# FORK-STORM-KILLS-HOOKS-01 — addendum: the producer is not `sleep`, it is a self-feeding watcher loop

Written 2026-09-01 after watching the storm happen live. The original brief named orphaned `sleep`
processes as the source and asked for a matcher pass over 52 hooks. **Both of those were my
assumption, and the second was wrong.** Correct them before doing that work.

## Correction 1 — the hook count was miscounted

The brief says "every tool call spawns 52 hook processes". That counted *wired commands*, not
*firing* ones. Counted properly, by matcher:

```
PreToolUse    fires-on-everything=1   matcher-scoped=35
PostToolUse   fires-on-everything=7   matcher-scoped=9
```

So an arbitrary tool call costs about **eight** hook processes, not 52 — the matchers are already
there. §3 of the brief (a matcher pass) is therefore mostly moot: do not spend the lane on it. If
anything remains, it is the 7 unscoped PostToolUse hooks, and each needs its own justification.

## Correction 2 — the real producer, measured live

Process count on this machine went **877 → 1629 in about one hour** with no user-visible cause. The
census at the peak:

```
orphaned watchers (ppid=1)                 24     (pulse-watch + single-lead-beat-loop)
of those older than one hour                6     (oldest 1h44m)
all leadv2 processes with ppid=1           44
```

And the event stream shows the mechanism, not just the symptom — **11 of the last 12 lane terminals
were `skipped:plan_source_absent`, arriving every ~30 seconds with a fresh sig**:

```
10:44:42 168e6ff1 skipped:plan_source_absent
10:47:25 63d2d136 skipped:plan_source_absent
10:47:33 11a33e92 skipped:plan_source_absent
10:48:33 70e97f3d skipped:plan_source_absent
10:49:06 1e2e19d8 skipped:plan_source_absent
10:50:11 0d546715 skipped:plan_source_absent
```

That is a **closed loop**, and it was reproduced by hand three times:

1. a dispatch spawns `leadv2-lane-pulse-watch.sh --sig <sig>`;
2. the watcher outlives its dispatch and is reparented to launchd (`ppid=1`);
3. lane liveness reads the pid recorded for that lane — which is **the watcher, not the worker** —
   and answers `live`;
4. the next dispatch for that lane refuses with `lane_is_live` and terminates
   `skipped:plan_source_absent`;
5. that attempt has already spawned its own watcher. Return to 2.

Killing the watcher does not break the loop: within the ~105s a dispatch takes, a new one appears.
Measured three times on `PLUGIN-PAPERCUTS-01` (`168e6ff1`), which is unrunnable because of it.

The same shape blocked `ARM-CAPABILITY-FROM-OUTCOMES-01` for 33 minutes, where the lane's "live"
pid was an orphaned `codex-task.sh __quota-watch`.

## What this changes about the fix

- **§2 stays and grows.** Reaping children on exit is necessary but not sufficient: the watcher is
  orphaned *by design* here — it is spawned detached so it can outlive the dispatch. Either it must
  be owned by something that dies with the lane, or it must self-terminate when its lane's worker is
  gone. Decide which from the runtime and say so in `report.md`.
- **Liveness must not key on a watcher pid.** This is the actual bug behind three separate
  "lane_is_live but nothing is running" incidents today. A lane is live when its *worker* is live; a
  watcher is not a worker. Whatever records the lane's pid must record which kind it is, and
  liveness must ignore the watcher kind.
- **`skipped:plan_source_absent` must be distinguishable from a real skip.** A lane skipped because
  a stale watcher makes it look live is a fault; today it is indistinguishable from a deliberate
  skip in the event stream.

## Acceptance additions

8. a dispatch that spawns a pulse watcher and then exits ⇒ the watcher does not survive to make the
   lane read `live` on the next dispatch (drive this with fixtures; this is the loop above);
9. a lane whose only live process is a watcher ⇒ liveness reports NOT live;
10. a skip caused by a stale watcher ⇒ carries a distinct cause, never bare
    `skipped:plan_source_absent`.

Everything in the original brief's Rules section still binds.
