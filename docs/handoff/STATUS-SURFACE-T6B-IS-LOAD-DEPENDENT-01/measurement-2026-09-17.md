# `tests/test-status-surface-bash32.sh` on main — 2026-09-17

```
rc=0  elapsed_s=721  ok=15
```

**Boundary:** leadv2 main, macOS, ceiling 2700s, one run, board live (349 dispatch dirs).

## Two things this settles, and one it creates

**1. The suite is green right now.** `_t6b` passed. That does not mean the defect is gone — it
means the two captures happened to agree on this run. That is the whole content of the row: the
case fails as a function of board state, not of code. A green run is the expected outcome most of
the time; the row exists because sometimes it is not.

**2. 721s is the honest runtime**, so the earlier premise-probe death at a 900s budget is not
simply "the suite is slower than the budget" — 721 < 900. Either the probe context costs extra
(the same unexplained gap measured on `test-review-arm-no-verdict.sh`: 45s standalone vs killed at
900s), or the two runs contended. Unresolved, and recorded as unresolved.

## The acceptance this row was filed with is unsound, and it is the row's own defect

The row's acceptance was `bash tests/test-status-surface-bash32.sh` — i.e. "the suite passes".

That criterion **can go green while the defect is fully present**, because the defect is exactly
that the case's outcome depends on load rather than on code. Attaching a load-dependent acceptance
to the row about a load-dependent criterion reproduces the mistake the row was filed to fix.

A sound acceptance for this row is **structural**: it must assert that both renders read one frozen
lane set, which cannot become true by luck. It therefore names a guard suite that does not exist
yet, and per standing practice must be written as `test -f <suite> && bash <suite>` so a missing
file is a dispatch refusal (`rc=127`) rather than a silently red acceptance.

Re-dispatched on that basis.
