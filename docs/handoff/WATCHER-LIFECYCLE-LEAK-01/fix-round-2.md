# Fix round 2 — root cause sharpened; GLM failed twice, escalated arm

Round-1 result: still selfcheck_failed. Lead re-ran the suite and measured:
- Suite itself warns "3 residual beat-loop(s) live from an earlier run".
- L1/L2 FAIL with live=4 = 1 real + 3 RESIDUE from prior runs: the liveness count
  is GLOBAL (matches every beat-loop on the machine), not scoped to the scenario's
  tmp repo. Residue from any earlier run permanently poisons L1/L2.
- Teardown leaks 3 loops per scenario ("L1 teardown: 3 loop(s) leaked"); after one
  suite run 26 processes from this worktree were alive. Lead had to `kill -9`.
- PRIMARY DEFECT, proven twice: the beat loop DOES NOT DIE ON SIGTERM (plain `kill`
  leaves it alive; only SIGKILL works). Likely cause: trap not firing while blocked
  in foreground `sleep` (bash runs traps only after the current command exits), or
  trap '' TERM inherited. L3 owner-death reap works; TERM does not.

Required fixes, in order:
1. Make the loop TERM-responsive: `sleep <interval> & wait $!` pattern with
   `trap 'kill $sleep_pid; cleanup; exit 0' TERM INT`, so TERM interrupts the wait
   immediately. Same for lane-pulse-watch.
2. Scope the test's liveness count to the scenario (match the tmp repo path in the
   process cmdline or use the pidfile), so machine-global residue cannot poison it.
   Keep the assertion strength: exactly 1 loop FOR THIS SCENARIO.
3. Suite teardown: trap EXIT kills every pid the suite spawned (TERM then KILL
   fallback); assert 0 residue at suite end and FAIL the suite otherwise.
Re-run: full suite green, negative control still RED, and after the suite
`pgrep -f "<worktree>/plugins.*beat-loop"` must print nothing.
