# THE-E2E-RUNG-CALLS-PRE-EXISTING-RED-A-REGRESSION-01

## Measured

Two lanes died today with `dispatch_terminal … cause=e2e_regression` (`0a148de1`, `e33f2050`),
in both cases AFTER their work was complete, correct and green on its own suites. The e2e rung
named three blocking failures:

```text
Failures (blocking):
  - plugins/leadv2/scripts/tests/run-core-offline.sh
  - tests/test-status-surface-bash32.sh
  - plugins/leadv2/tests/test-complexity-source-provenance.sh
```

All three are red on `main`. **None of them is a regression.** Verified at the commit immediately
before the merge under suspicion (`b0fd0784^1` = `ac0c0bae`), in a detached worktree:

```text
test-complexity-source-provenance.sh @pre-merge  rc=1
test-status-surface-bash32.sh        @pre-merge  rc=1
```

Both were already red. `run-core-offline.sh` does not finish inside 300s (rc=124). And none of the
three is listed in `tests/known-red-suites.txt` (47 lines, dated 2026-09-02, whose stated purpose is
exactly "suites that were ALREADY red on main the day CI was wired up").

So the rung's verdict is not merely noisy — it is **wrong in a specific, expensive way**: it reports
"regression" for a condition that predates the change, and the lane is killed on that verdict.
Related standing row: `SD-MAIN-CORE-SUITE-RED-01` (OVERDUE since 2026-09-01, 16/85 red on main).

## What to build

### 1. A verdict that distinguishes new red from old red

The rung must compare against a baseline, not against green. A suite that was red at the lane's
merge-base is `known_red`, not `regression`. Concretely: the terminal cause must be able to say
`e2e_known_red` (work is fine, debt is old) separately from `e2e_regression` (this change broke it),
and a lane must not be killed by the former.

- The baseline must be the lane's own merge-base, computed, not a hand-kept list that rots.
  `tests/known-red-suites.txt` may remain as a coarse skip list, but it must not be the only
  mechanism — it is dated 2026-09-02 and already misses these three.
- A suite that TIMES OUT (`rc=124`) is a third state, not a failure: report `e2e_timeout` with the
  suite name and the budget it exceeded. `run-core-offline.sh` exceeds 300s today.

### 2. Say which suites, in the terminal line

`cause=e2e_regression` alone sent me to read four artifacts to learn which suites failed. The
terminal event must carry the failing suite names (or the artifact path) so the next reader does
not repeat that.

### 3. Then triage the three, honestly

For each of the three: is it a real defect or a harness/environment failure? One datum to start
from — `test-complexity-source-provenance.sh` fails every case with `no route_resolved line`
(b1–b5), i.e. the harness produces no decision at all rather than a wrong one, which smells
environmental rather than a provenance bug. Prove it either way.

Outcome per suite, and nothing else is acceptable: FIXED (with the diff), or LISTED as known-red
with a dated one-line reason and a ledger row for its repair. Do not add a suite to the skip list
without that row — a skip list without owners is how these three became invisible.

## Method — binding

- The question "is this a regression?" is answered ONLY by running the suite at the merge-base.
  A suite being red now proves nothing about who made it red.
- Name the surface of every count.
- Negative control by mutation inside the function body; strip comments when grepping.

## Acceptance

1. A lane whose work is green but whose merge-base is red terminates with `e2e_known_red`, not
   `e2e_regression` — demonstrated, not asserted.
2. The terminal line names the failing suites.
3. A timeout is reported as a timeout, with the budget.
4. Each of the three suites is FIXED or LISTED-with-a-row.
5. Still green: `test-launcher-refusal-event.sh`, `test-arbiter-decision-record-inputs.sh`,
   `test-reset-urgency.sh`, `test-leadv2-task-judge.sh`, `test-arbiter-prices-by-provider.sh`.

## Off limits

- Silencing the rung altogether, or allow-listing everything red. The goal is a TRUE verdict, not a
  quiet one.
- `reset_urgency`, `provider_cost`, decision-record schema v2, the launcher-refusal event, the
  judge's noisy-envelope parser — all landed today.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
