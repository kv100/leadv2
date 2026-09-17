# FOUR-SUITES-RED-ON-MAIN-BLOCK-EVERY-ARBITER-LANE-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## What was measured

Four suites are red on leadv2 **main** as of 2026-09-16 and killed lane `cdd7a22b` with a false
`terminal=dead cause=e2e_regression`:

| suite | main | merged |
|---|---|---|
| `plugins/leadv2/tests/test-arm-pool-reachability.sh` | rc=1 | rc=1 |
| `plugins/leadv2/tests/test-exclusion-stages.sh` | rc=1 | rc=1 |
| `plugins/leadv2/scripts/tests/test-arbiter-seam-plugin-kind.sh` | rc=1 | rc=1 |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | **rc=124** | **rc=124** |

The pairing is against the **merge result** of `worktree-26647d0efbb6`, not against the branch —
the branch lags main by the bands merge, so a branch-side comparison would have manufactured a
difference that is really just main being newer. Identical on both sides, so none of it is any
lane's doing.

All four were allow-listed in `tests/known-red-suites.txt` by commit `9312f6cb` under the founder
standing decision `SD-MAIN-CORE-SUITE-RED-01` (2026-09-01: land, and file a row). **This is that
row.** Repairing them means removing their four entries from the allow-list in the same diff — an
allow-list entry that outlives its cause is how a red suite becomes permanent.

## `run-core-offline.sh` is a different animal and you must treat it as one

`rc=124` is a **timeout of the meta-runner at a 420s budget**, not an assertion failure. It is not
"the suite is red"; it is "nobody knows whether the suite is red, and the allow-list is recording
that ignorance as a known failure". A timeout is a third verdict and the allow-list has no way to
express it.

Two sub-questions, and they have different answers:

1. Does the suite actually pass when given enough time? Measure it. Run it with a generous ceiling
   and report `rc`, counts, and the wall-clock it needed. If it passes at 900s, the defect is the
   420s budget, not the suite.
2. If it does not pass, what is genuinely red inside it? Then it belongs with the other three.

Either way, **state the ceiling you applied with every count you report.** A count without its
boundary has been the single most common lie in this repo's test reporting.

## The other three may not be yours to fix — establish that before you try

`ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01` (`da0acd521f24`) is **live right now** and is
rewriting arm selection, including reachability of the top arms. `test-arm-pool-reachability.sh`
and `test-exclusion-stages.sh` are about exactly that seam.

So for each of the three: read the failure, and decide which of these it is —

- **the suite encodes a superseded requirement** → the suite is the defect, fix it here;
- **the production code is genuinely wrong and the fix lives in `leadv2-route-arbiter.sh`** → you
  may NOT fix it here (that file is held). Write the attribution as a finding, name the exact
  function and line, and leave the suite red and named. That is a complete result, not a failure.
- **it will resolve itself when the arbiter lane lands** → say so, and say what you ran to believe
  it.

Guessing between these three without reading the failure output is the thing that must not happen.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not touch `plugins/leadv2/scripts/leadv2-route-arbiter.sh`,
  `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh` or `leadv2-dispatch-product-close.sh` —
  live lanes hold all four.
- Do not remove an allow-list entry for a suite you did not actually repair. Removing the entry is
  the claim that the suite is green; make the claim only where you can show the green run.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. **A suite you repaired is genuinely repaired** → mutate the production code it guards, inside
   the function body in the lane worktree, and confirm the suite goes red. Assert the mutation
   target string is present first, so the control cannot rot into a permanent green.
2. **The allow-list still works** → re-add one removed entry and confirm the runner treats it as
   known-red again, then remove it. This proves the removal was the thing that changed the
   verdict, not something incidental.

Never mutate a scratch copy — this family was measured to behave differently in a detached
worktree at the same commit.

## Deliverable

`docs/handoff/FOUR-SUITES-RED-ON-MAIN-BLOCK-EVERY-ARBITER-LANE-01/report.md` — per-suite verdict
with before/after counts and their ceiling, the `run-core-offline.sh` timing measurement with the
ceiling that made it pass (or the red it produced once given time), an explicit attribution line
for each suite you did NOT repair naming the file and function where its fix belongs, the
allow-list entries removed and why each removal is safe, and both controls with pasted output.
