# ARM-PRODUCES-NOTHING-02 fix round 1 — the new guard is FLAKY, which makes it not a guard

Resume the work already in `.claude/worktrees/99bf56d6` (360 insertions / 22 deletions across
`leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh`, `tests/test-lane-diff-single-repo.sh`).
Do not start over. The design is right and the hard requirement is met.

## What is already good — keep it

`C3-clean-anti-rescue` is **GREEN in both passes**. That is the requirement the previous attempt
failed and the reason `3bffb24` had to be reverted from main. Do not disturb it.

The e2e gate passed (`e2e-gate-passed.flag`). `review-gate.md` says
`status: no_reviewer / refusal: all_review_arms_unavailable` — that is the codex quota lockout until
2026-08-08, not a finding against your work. Nothing for you to fix there.

## The one blocker

`tests/test-lane-diff-single-repo.sh` runs the case list twice. Your new case behaves differently
between the two passes:

```
pass 1: PASS C1  PASS C2  PASS C3  PASS C4  PASS C5-registered-arm-silent
pass 2: PASS C1  PASS C2  PASS C3  PASS C4  FAIL C5-registered-arm-silent
```

C5 is the case that encodes the whole decision — arm registered + clean worktree + no stream =>
`arm_produced_nothing`, versus no arm registered => `no_work`. **A guard that passes only sometimes
is not a guard**, and this one is guarding against exactly the failure mode where a lane silently
produces nothing. Shipping it flaky would mean the next silent glm lane may or may not be caught,
with no way to tell which.

Find why the second pass differs. Likely candidates, in the order worth checking: state left behind
by pass 1 that pass 2 inherits (an arm-registration marker, receipt, lock, or temp dir not cleaned
between passes); an ordering or timing dependence; or a check that reads a real path instead of the
fixture's. Fix the cause — do not make the case tolerant of both outcomes, and do not run it only
once to hide the difference.

## Done means

- `test-lane-diff-single-repo.sh`: all cases pass in BOTH passes, including C5, with C3 still green.
- One sentence in your report naming the actual cause of the flake. "Made it deterministic" without
  a cause is not an answer — if the cause is shared state between passes, say which state.
- The dispatch/lane suites only. Do NOT run `run-core-offline.sh` — its failures are the codex
  lockout.

## Constraints

- No commit, no push. The lead merges.
