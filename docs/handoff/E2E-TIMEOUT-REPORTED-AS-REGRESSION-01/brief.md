# E2E-TIMEOUT-REPORTED-AS-REGRESSION-01

The e2e gate reports a command timeout as a test regression, kills the lane, and the round's work
is lost. It happened tonight and cost a full round.

## Measured, 2026-09-03

Lane `SAFETY-PIN-SECOND-DOOR-01`, dispatch `49c6e0c8`. From its journal, in order:

    selfcheck        task=49c6e0c8 status=green checks=7 skipped=2
    e2e_gate         task=49c6e0c8 status=ran verdict=fail rc=124
    dispatch_terminal task=49c6e0c8 terminal=dead cause=e2e_regression
                      worker_reason="Running the changed-scope suite in the backg…"

`rc=124` is the exit code `timeout(1)` returns when it kills a command. It means the sweep did not
finish; it does **not** mean a test failed. The lane's own self-check had just passed green with 7
checks. The lane was closed as `cause=e2e_regression` and its worktree held only the anchor commit
afterwards.

The two states need opposite responses. A regression means stop and fix the code. A timeout means
the budget was too small or the sweep too wide — the code may be perfectly fine. Reporting one as
the other sends the next session hunting a bug that does not exist, and throws away the round.

## What this task must deliver

1. **Separate the two.** `rc=124` (and any other timeout signal the gate can produce) must land as
   its own cause — `e2e_timeout` or similar — never `e2e_regression`. Name the file:line.
2. **Decide what a timeout should do to the lane**, and argue it in the report. A timeout is not
   evidence of breakage, so killing the lane and discarding the round is probably wrong; but
   silently passing it would be lying-green. A defensible answer might be: record the timeout,
   keep the lane's work, and mark the gate `unknown` so a human decides. Pick one and justify it.
3. **The round's work must survive either way.** In the measured case the lane ended with only its
   anchor commit. Whatever verdict the gate reaches, what the worker produced must be committed.
4. **Say why the sweep timed out** — a one-line diagnosis is enough. If the gate runs a full
   `run-all --scope changed` inside a lane, say so and say whether that is the intended budget.
   Do not fix it by raising the timeout alone; that hides the shape of the problem.
5. **A negative control**: simulate a gate command that exits 124, show the lane is classified as a
   timeout and its work survives; revert, show a real failing test still classifies as a
   regression. Both directions, red then green.
6. Green on macOS and in a Linux container, exit codes pasted. Register any new suite in
   `tests/run-all.sh` and prove `--scope changed` selects it.
7. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, weakening assertions, and making the gate pass on
a timeout without recording it.
