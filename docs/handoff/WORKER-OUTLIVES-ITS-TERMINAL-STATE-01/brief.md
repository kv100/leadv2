# WORKER-OUTLIVES-ITS-TERMINAL-STATE-01

A worker can record a terminal state, keep working after it, and then stay alive indefinitely
holding the lane. It cost real work twice in one night and blocked a lane from ever being
re-dispatched.

## Measured, 2026-09-03

Lane `LANE-PLACEMENT-PIN-RED-01`, dispatch `8b995f4a`. The journal records:

    arm_advance   task=8b995f4a from=codex to=sonnet reason=arm_produced_nothing
    review_gate   task=8b995f4a status=blocked reason=no_work terminal=no_work cause=empty_diff

Eighty-three minutes later, PID 65371 was still alive. Its last stream entry read
`"result":"Waiting for the Monitor notification."`, `lsof` showed it holding
`docs/handoff/dispatch-8b995f4a/developer.stream.jsonl` open for writing, and the lane worktree
held **52 lines of uncommitted work** — real changes to `leadv2-dispatch-code.sh` and 43 new lines
in `test-lane-placement-pin.sh`. The lead committed them verbatim as `b794a736`; a later round
verified them and they are now on `main`.

So the terminal state was recorded **before** the worker had finished, and the work it produced
afterwards was invisible to every mechanism that looks at lane outcome.

## The second consequence, which is what made it expensive

Because the process stayed alive holding the stream open, `leadv2-lane-liveness.sh` kept
returning `verdict: alive, reason: log_fresh` — `silent_max` is 900s and the file never went
quiet. Every re-dispatch was refused with `lane_placement_refused reason=lane_is_live`.
Unregistering the row from `active.yaml` did nothing, because liveness is not read from there.
The lead waited a blind 16 minutes without touching the lane and the window did not move. The
lane only became dispatchable after the lead killed PID 65371 by hand, at which point liveness
flipped to `sentinel_finalized` immediately.

The freepool lane suffered the same shape earlier the same night: round 1 was reaped
`worker_died_stale` holding 25 uncommitted files.

## What this task must deliver

1. **Find out why a terminal state is recorded while the worker is still producing.** That is the
   root cause; the rest is damage control. Name the file:line that records it and say what it
   observed. `arm_produced_nothing` was demonstrably false at the time it was written.
2. **A worker that has recorded a terminal state must not stay alive.** Either it exits, or the
   dispatcher reaps it. "Waiting for the Monitor notification" forever is not an acceptable
   resting state for a process that has already been declared done.
3. **Work must not be lost in the gap.** Whatever the fix to (1), a worker's changes must end up
   committed even if the terminal state was recorded early — the lead should never again be the
   mechanism that rescues 52 lines by hand.
4. **A negative control per claimed fix**: name the mutation, show red, revert, show green. For
   (2), a test that a worker with a recorded terminal state is gone within a bounded time.
5. Green on macOS and in a Linux container, exit codes pasted. Register any new suite in
   `tests/run-all.sh` and prove `--scope changed` selects it.
6. Commit in this lane before you finish. This task in particular.

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, and raising `silent_max`
to paper over (2) — the window is not the bug, the immortal process is.
