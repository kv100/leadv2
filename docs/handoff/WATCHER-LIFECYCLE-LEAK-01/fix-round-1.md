# Fix round 1 — L1/L2 falsification failures (selfcheck_failed)

Re-run evidence (2026-09-01T02:45Z, lane worktree):
- L1 singleton FAIL: `live=4 second_exited=yes`, log shows BOTH `spawn` (pid 6726)
  and `dedup_refused` (pid 6779) — dedup logic works, but the LIVE COUNT is 4, not 1.
- L2 arm storm FAIL: `live=4 pidfile_alive=yes`.
- L3-L7 PASS (owner self-reap, lane-pulse singleton, no-growth, negative control).

Diagnose WHY live=4 when only one loop should exist. Two suspects to check first:
1. The loop implementation spawns a process group (bash wrapper + subshell + sleep +
   tee?) and the test's liveness count matches all of them — then either make the loop
   a single process (exec, no pipeline) or count only the loop leader pid.
2. Residual loops from a previous test scenario are not killed between scenarios —
   then the fix is in the reaper, not the test.
Fix the CODE if the count is real; fix the TEST only if the extra pids are provably
the test harness's own scaffolding. Then re-run the whole suite: 8/8 must pass with
the negative control still RED. Do not weaken L1/L2 assertions.

## Additional live evidence (2026-09-01T02:50Z)
After the test suite ran, THREE `leadv2-single-lead-beat-loop.sh` processes from THIS
lane worktree stayed alive ~28 min (pids 13642/38613/79709, killed by the lead). This
proves suspect #2: the test harness (or the loop itself) leaves residual loops between
scenarios — the L1/L2 `live=4` count is REAL leakage, not test scaffolding. The suite
must also reap its own spawns in teardown (trap EXIT), and the loop must honor owner
death even when the owner is a short-lived test scenario.

**Update:** plain SIGTERM did NOT kill these loops (survived `kill`); SIGKILL required. The loop (or its modified trap handling in this diff) ignores/mishandles TERM — fix must ensure TERM terminates the loop promptly.
