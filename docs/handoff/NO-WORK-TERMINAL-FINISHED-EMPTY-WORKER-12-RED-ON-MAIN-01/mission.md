# NO-WORK-TERMINAL-FINISHED-EMPTY-WORKER-12-RED-ON-MAIN-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## Measured on main, today, by the lead — not inherited from a report

```
test-no-work-terminal.sh      rc=1  pass=46  fail=12
test-parked-worker-resume.sh  rc=0  pass=9   fail=0
```

Both suites belonged to row `088197b5e53d`, which was **closed** while the first was still red. Its
own close record says so outright: *"The repository does NOT prove the underlying work was done or
accepted: no acceptance probe passed for this close."* The second suite is genuinely fixed; leave
it alone and run it as a regression check before and after, pasting both.

## The premise of the old row is STALE — do not work from it

`088197b5e53d` named three failing cases: `partial_diff` coming back `status blocked`, and
`revived` / `revive_blocked_by_gate` waiting to timeout instead of finalizing. **None of those is
what fails today.** The twelve current failures are headed by:

```
[TEST] FAIL: finished empty worker exits 5 (got '0' want '5')
[TEST] FAIL: finished empty worker missing no_work gate
[TEST] FAIL: finished empty worker terminal missing
[TEST] FAIL: finished empty worker ledger row missing
[TEST] FAIL: codex finished-empty path remains no_work (got '0' want '5')
[TEST] FAIL: codex liveness probe called only 2 times
```

The suite itself was rewritten by `65c081d9` (*fix(close): resolve symlinked declared writes to
their physical repo; recalibrate revive hang bound*), which touched **both the suite and its
subjects**. So the old premise went stale — that is **not** the same claim as "the fix regressed",
and the two need opposite responses. **Establish which, by measurement, before writing anything**,
and state the verdict in one sentence at the top of the report.

## Read the failure names precisely

`finished empty worker exits 5 (got '0' want '5')` says the worker exited **0** where the contract
wants **5**. Exit 5 is the `no_work` terminal. So the path is not *mis-reporting* no-work — it is
**not reaching the no-work verdict at all**, and the three siblings (`missing no_work gate`,
`terminal missing`, `ledger row missing`) are consistent with a single early return rather than
four independent bugs. Prove or disprove that before fixing four things.

`codex liveness probe called only 2 times` is a different shape — a count, not a verdict. Do not
fold it into the same cause to make the count tidier; if it turns out separate, say so.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
  A case that cannot be fixed honestly stays red and is named as still-red with its cause.
- Do **not** touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
  `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`,
  `plugins/leadv2/scripts/leadv2-review-run.sh`,
  `plugins/leadv2/scripts/leadv2-active-registry.sh`, or
  `plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh` — other lanes hold all five.
- `test-parked-worker-resume.sh` is green. Making it red is a failure of this lane regardless of
  what else turns green.

## Controls

At least two independent claims (the single-early-return cause, and the codex probe count if it is
separate) → one negative control each, RUN, outputs pasted. Apply each mutation inside the function
body **in the lane worktree**, never a scratch copy. Assert the mutation target string is present
before running, so a control cannot rot into a permanent green against text that no longer exists.

## Deliverable

`docs/handoff/NO-WORK-TERMINAL-FINISHED-EMPTY-WORKER-12-RED-ON-MAIN-01/report.md` — the
stale-premise-vs-regression verdict with the evidence that settled it, whether the four
`finished empty worker` failures are one cause or four, before/after counts for **both** suites
with their boundary (counts, ceiling, platform, commit), the controls with pasted output, and any
case left red with its cause.
