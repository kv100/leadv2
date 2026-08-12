# PLUGIN-RELIABILITY-02 — finish the zombie-reaper (closed mission from judge verdict)

Base: the UNMERGED worktree `worktree-PLUGIN-RELIABILITY-01` (branch, 3 commits up to
c6c44b5) carries the liveness rework; review round-2 + judge (HOLD_UNMERGED, verified in
source) found the reap half is a silent no-op. Start FROM that branch (cherry-pick or
branch off it), do exactly the five items below — nothing else:

1. product-close.sh:1494 AND :1516 — `_pc_reap_worker` is called with `"${HANDLE}"` but
   its signature (declared at :783) takes `<run_dir>`; it reads `${run_dir}/pgid` and
   `${run_dir}/.lockref`, so both timeout call sites currently reap nothing. Pass the
   resolved run dir (`${_PC_RUNS_ROOT:-${RUNS_ROOT:-${ROOT}}}/${AUTHOR}-runs/${HANDLE}`
   or the variable product-close already holds for it — verify against how the run dir
   is created at spawn).
2. pgid values are setsid process-GROUP ids but are signalled as bare pids (~:813).
   Signal groups as groups: `kill -TERM -"${_pid}"` / `kill -KILL -"${_pid}"` for
   pgid-sourced entries; keep bare-pid signalling for the meta pid.
3. Reorder the meta-absent grace branch (~:891) to run AFTER the `_PC_ASKED_INTO_VOID`
   terminal-evidence branch (~:913) so legacy terminal evidence still wins.
4. Test harness :436 — `TASK` is never set though the header claims it; the
   SIGKILL-escalation path expands `${TASK}` and aborts under `set -u`. Set it.
5. Tests MUST be behavioral, and the gate is: a test that FAILS against c6c44b5 and
   PASSES against your fix. Fork a real sleeper via setsid, write real pgid/.lockref
   files into a sandbox run dir, invoke the REAL timeout call-site path, assert the
   group child is gone. Any grep-on-source test is rejected on sight (two lanes died on
   this exact lying-green pattern today).

Proof: new suite rc=0 + the against-c6c44b5 red/green demonstration in the summary +
`bash plugins/leadv2/scripts/tests/run-core-offline.sh` rc=0.

Deliverable: commits + docs/handoff/PLUGIN-RELIABILITY-02/summary.md, DELIVERABLE_COMPLETE.
