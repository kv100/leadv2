# MON-PULSE-01 fix-round 3 — H-1 + H-2 (final)

**H-1** test launchers (`run_loop`, `arm_root`) now `exec bash "$LOOP"` so `$!` IS the loop pid; `cleanup` also kills pidfile owners; `wait_gone` FATAL (no `|| true`).
**H-2** reader errors (missing / unparseable / error-object heartbeat) keep beating, never count toward a stop; UNKNOWN_MAX stop removed — only ZERO_MAX consecutive real zeros stop.

Raw tails, 3 consecutive suite runs:
```
run1 [TEST] PASS: B8 reader errors: 5+ unknown passes, loop still alive and beating (H-2)
     test-single-lead-beat-loop: 9 passed, 0 failed  rc=0
run2 [TEST] PASS: B8 ... (H-2)
     test-single-lead-beat-loop: 9 passed, 0 failed  rc=0
run3 [TEST] PASS: B8 ... (H-2)
     test-single-lead-beat-loop: 9 passed, 0 failed  rc=0
```
Negative control (H-2 reverted): `[TEST] FAIL: B8 ... alive=no` / `8 passed, 1 failed` — red by design.

Orphans: `pgrep -f "d56bf8bc.*single-lead-beat-loop"` after 3 runs → **0**. (10 procs from worktree 5aeaa8bb — a concurrent lane's own live suite; not killed, not ours.)

Self-check: `bash -n` OK both files; no Python changed. `run-all --scope changed`: 4 passed, 1 failed — `run-core-offline.sh` (9 internal failures, all dispatch-core areas untouched by this diff; pre-existing baseline reds + concurrent-lane lock interference: `waiting for lock ... held by a concurrent run`).
