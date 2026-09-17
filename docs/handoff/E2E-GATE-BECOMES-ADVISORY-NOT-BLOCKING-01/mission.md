# E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**This is a founder decision (2026-09-17), not a proposal.** Your job is to implement it correctly
and to guard it, not to re-litigate whether the gate should block.

## The change, precisely

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, the e2e branch around `:4139-4156`.

Two sibling branches exist today:

- `:4128-4131` — the **pre-existing-red** branch. It emits `pre_existing_red task=… suite=…
  baseline=merge_base` per suite and its own comment says: *"NOT dead, NOT exit 8 — falls through
  to the review gate below."*
- `:4139-4156` — the **failing** branch. It writes `e2e-gate.md` with `status: fail
  reason: e2e_regression`, names the failing suites, then calls `_dl_note dead e2e_regression …`
  and `exit 8`.

**Make the second branch behave like the first in its terminal effect and only that.** Keep
`e2e-gate.md` exactly as it is written today, keep the journal line, keep the failing-suite names.
Remove the `dead` terminal and the `exit 8` so the lane falls through to the review gate.

What must NOT change:
- the kill-switch branch (`E2E_ON != 1`) — a deliberately disabled gate is a different state and
  must keep its current meaning;
- the `pre_existing_red` branch;
- the `e2e_timeout` path — that is a separate row (`04711956090b`) and is not yours;
- anything about `review_gate`. Review remains the judge and must keep its ability to kill.

## Why, in measured terms — put this in the report

- Of **24** lanes killed with `e2e_regression`, **22** were resolvable and **22/22 reproduced red
  on `main`**. Zero confirmed genuine catches.
- One case was pushed further: lane `3e74b0ce`, base `e1baab7c`, exported with `git archive` into a
  clean directory (no shared tree, no sibling worktrees) — `test-arm-pool-reachability.sh` gave
  `rc=1 pass=3 fail=17`, identical to `main` today. So that kill was foreign **at the time**, not
  an artifact of current machine load.
- Gate cost: **101.1 hours, ≈12.7%** of lane wall-clock; pass rate **11%** (12 of 112 runs).
- Review is **not** silent and keeps judging: **18** `review_gate status=fail`, plus terminal
  causes `review_verdict_fail` **11** and `review_dod_fail` **3**.

## The bootstrap problem — read before you start

This lane changes the gate that will run against this lane. If the gate kills you with
`e2e_regression` on a suite that is red on `main`, that is the defect you are fixing, demonstrating
itself. **Do not work around it by weakening anything.** Write the fix, write the guard suite, and
report. The lead will handle landing, and an e2e kill of this specific lane is expected evidence,
not a failure of your work.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not remove the gate, its run, its log, or its artifacts. Advisory means **reported and not
  fatal**, never **not measured**.
- Do not touch `leadv2-dispatch-code.sh`, `leadv2-active-registry.sh` or `leadv2-route-arbiter.sh`.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. **A lane with a red e2e no longer dies at the gate.** Revert your change and confirm the `dead`
   terminal plus `exit 8` return.
2. **Review can still kill.** Mutate the review-gate fail path inside the function body and confirm
   a failing review still produces a non-landed terminal. The whole safety of this change rests on
   review remaining fatal — prove it, do not assert it.

Apply each mutation inside the function body in the lane worktree, never a scratch copy. Assert the
mutation target string is present before running, so a control cannot rot into a permanent green.

## Deliverable

`docs/handoff/E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01/report.md`, plus a new guard suite
`plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh` that pins: a red e2e verdict is written
to `e2e-gate.md`, is journalled, and does **not** produce a `dead` terminal; and that a failing
review still does. State how CI selects it on a change to `leadv2-dispatch-product-close.sh`.
