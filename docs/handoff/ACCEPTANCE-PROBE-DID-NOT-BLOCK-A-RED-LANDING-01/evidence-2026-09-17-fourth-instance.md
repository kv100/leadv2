# Fourth instance, and the first with the acceptance provably attached

Measured 2026-09-17 by the lead. This is evidence for
`ACCEPTANCE-PROBE-DID-NOT-BLOCK-A-RED-LANDING-01` (`1fdca3ca1997`), collected while the lane was
still fresh. The row itself is blocked behind `leadv2-dispatch-code.sh` and cannot be dispatched yet.

## What happened

Lane `66f31ff9aca5` (sig `e8cc317d`, `LANE-TRUTH-BATCH-01-MUTATION-GATE-HEAD-STILL-RED-01`) was
dispatched **by the lead** with an explicit acceptance:

```
--acceptance-cmd "cd /Users/kostiantyn.vlasenko/Projects/leadv2 && \
                  /bin/bash /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh"
```

Expectation `rc==0`. The lane reported:

> **NOT REPRODUCED** — the "Row 1 mutation gate HEAD" case is green at every clean tree tested,
> including a byte-exact export of `79d0986f` … so this lane changed zero code and the assertion now
> passes for the right reason.

Review gate: `review_gate task=e8cc317d status=ran author=glm-flash reviewer=fable
verdict=PASS_WITH_NITS`. Terminal: `dispatch_terminal task=e8cc317d terminal=landed
cause=review_verdict_pass`. Merge `0c033894`.

## The measurement that contradicts it

Two independent runs **at the merge commit itself**, both with the suite's own unpiped exit code:

| where | result |
|---|---|
| shared tree `~/Projects/leadv2` @ `0c033894` | `rc=1  pass=15  fail=1` |
| byte-exact `git archive 0c033894` into a clean dir | `rc=1  pass=15  fail=1` |

Both fail the same assertion: `Row 1 mutation gate HEAD must resolve stamped stream alive`.

The obvious defence — "the lead ran it in the dirty shared tree" — was **tested and falsified**: the
clean export of the same commit gives the identical count. Whatever environment produced the lane's
greens, it is not the tree that the merge commit describes, and it is not the tree the census
measures.

## Why this instance matters more than the previous three

- `55de339ac133` landed with the second of two named suites red (verified 4×).
- `088197b5e53d` was closed with one of two suites red (its close record disclaims proof).
- `f11c97a14f88` landed a half-fix (recorded as partial, deliberately).
- **This one** had the acceptance attached at dispatch, by hand, with a known-red baseline — and the
  landing happened anyway.

So the failure is not "nobody attached an acceptance". It is that **an attached, red acceptance does
not block the landing**. The consequence is that the word `terminal=landed` carries no information
about whether the work is done, for any lane in this session or before it.

## For whoever takes the row

The question to answer first, by looking: at close time, is the acceptance command **run and its
exit code ignored**, or **not run at all**? Those need opposite fixes, and the journal does not say —
no `acceptance_probe` line appears between `review_gate` and `dispatch_terminal` for this lane.
Check `leadv2-dispatch-product-close.sh` and the close gate in `leadv2-dispatch-code.sh` before
theorising.

Second: a lane that reports NOT REPRODUCED is a legitimate and valuable outcome — the rules
explicitly ask for it. But it must be **falsifiable against the commit it lands on**. Consider
requiring a non-reproduction claim to carry the acceptance's own output at the lane's HEAD, so a
false negative cannot pass as a stop-and-report.
