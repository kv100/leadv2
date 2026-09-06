# HARNESS-COSTS-MORE-THAN-IT-CATCHES-01

Repos: `~/Projects/leadv2` and `~/Projects/persona-engine`. BOTH are SHARED TREES — never
`git add -A`, never `reset --hard`, never `clean`, never `stash`, never push to origin. Name every
path in `git add`, then confirm with `git diff --cached --name-only`.

**COMMIT AFTER EVERY STEP.** Workers on this machine die on the last mile, after the work and before
the evidence. Commit each measurement as you get it.

## The founder's question, and why this lane exists

He asked, in plain words: are these tests real, or are we paying for fiction? The numbers that
prompted it, measured 2026-09-06 in persona-engine:

    suite files (tests/unit + tests/contract)      723
    entries in tests/mutations/catalog.yaml         39
    entries in tests/known-failures.txt             72
    suites red on main (per SD-MAIN-CORE-SUITE-RED-01)   16 of 85

A suite is proven only where a mutation shows it going red. That proof exists for 39 things out of
723 files. The rest are unmeasured — not proven worthless, but not proven either.

We already lived the failure this predicts: `19/21 COVERED` was theatre. It checked that assertion
*strings existed* while three real production mutations shipped through it green.

**And the tax is being paid right now.** On 2026-09-06 lane `B0-READER-HALF-01` was stamped
`terminal=dead cause=e2e_regression` while its worker had delivered. The red was one case of its own
suite — `a genuine concurrent arm is refused while the first owns the arm lock`, which holds the arm
for `PULSE_TEST_ARM_HOLD_S=1` and retries twice, so on a loaded machine the first arm expires before
the second attempts. The test measured machine load, not code. It cost the lead ~40 minutes and the
lane a false death certificate.

## What to deliver, in this order

**1. The baseline number, honestly measured.** Run `scripts/mutation-kill-rate.sh` over the whole
catalog. Report the kill rate with its denominator, and name every catalog entry that does NOT kill.
An entry that no longer kills is the most valuable line in your report: it is a suite that has
stopped protecting the thing it was written for, and nobody would have noticed.

**2. Classify all 16 reds on main.** Each into exactly one bucket, with evidence:
   - **a real defect in production code** — then the suite is doing its job; file a row, do not fix.
   - **a defect in the test itself** — wrong assertion, stale fixture, obsolete expectation.
   - **environment-coupled** — a timing race, a shared lock, a dependence on machine load or on
     another suite running. The B0 case above is the template.
   Fix bucket 2 and 3. Leave bucket 1 to its own rows.

   **`tests/known-red-suites.txt` and `tests/known-failures.txt` may only SHRINK.** Quarantining a
   red by listing it is forbidden — that is how the lying-green disease starts. Fix it or file it.

**3. The gate must not charge a lane for a red it did not cause.** This is the change that stops the
bleeding, and it is the centrepiece. Today a lane fails `e2e_regression` on any red, including the
16 that were already red on main before the lane existed. Make the gate compare against the red set
of the lane's own merge-base, so only a NEW red fails a lane.

   Negative control, and it is mandatory: **a lane that genuinely breaks a previously-green suite
   must still fail.** A change that merely stops failing lanes passes the first test and destroys the
   gate. Both colours, shown.

**4. The runtime bill.** `SUITE_TIMEOUT_S` is 120s and six of ten suites the lead sampled hit a
180s wall; two suite processes on this machine have been running 10 and 12 hours. Report the ten
slowest suites with their times. Do not optimise them in this lane — name them.

## Discipline

- `rc=0` means nothing. Read the summary line; `rc=$?` after a pipe reads the LAST stage's status.
- Never let `head` truncate a listing you are about to call complete. Capture to a file and grep it.
- A mutation must go INSIDE the changed function's body. A line-number insert landing at top level
  makes every suite red for the wrong reason and reads as a pass — this exact error invalidated a
  measurement on 2026-08-25.
- Derive every zero a second way.

## Report

`docs/handoff/HARNESS-COSTS-MORE-THAN-IT-CATCHES-01/report.md`, under 120 lines: the kill rate with
its denominator, the non-killing catalog entries, the 16 reds in their three buckets, the gate change
with both colours of its control, and the ten slowest suites. Then one paragraph answering the
founder's question directly, in plain words, with the numbers you actually measured — not the ones in
this brief.
