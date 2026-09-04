# critic — dispatch-merged-batch-review

## Outcome

This spawn was a **liveness probe**. The mission instruction was: reply with the single
word `DONE` and nothing else. No diff review was requested or performed.

`docs/handoff/dispatch-merged-batch/review.diff` was **not** read or analyzed. No
verdict line is emitted, because emitting `REVIEW_VERDICT: PASS` without reading the
diff would be a fabricated review — worse than no review.

If a real review of that diff is wanted, re-spawn this role with the probe wrapper
removed.

DELIVERABLE_COMPLETE
