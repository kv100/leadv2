# `test-lane-writes-scoping.sh` on main, ceiling 1800s — 2026-09-17

Measured by the lead directly on leadv2 **main**, not from any lane report.

```
MAIN test-lane-writes-scoping rc=1
pass=4 fail=2
[TEST] FAIL: M7 -- post-fix rc=1, expected 0
FAIL: M7: post-fix did not pass (rc=1)
red=4 green-pre-fix=12 could-not-run=0
```

**Boundary:** leadv2 main, macOS, ceiling 1800s, one run.

## What this corrects

An earlier run of this same suite returned `rc=124`. That was a **timeout of the ceiling I
imposed**, not a failure of the suite — a third verdict, neither pass nor fail. At 1800s the suite
completes and produces a real verdict. Any earlier statement that read that `124` as "red" is
wrong; this line is the verdict.

## What is actually red

One case: **M7**, `post-fix rc=1, expected 0`. Subject log was written to a `/var/folders/...`
temp path that does not survive; re-running is the way to see it, not recovering that file.

## What `green-pre-fix=12` is, and what it is not

The suite classifies every case into `red` / `green-pre-fix` / `could-not-run` and prints the
counts. `green-pre-fix=12` means twelve cases passed against HEAD **as well as** against the
fixed tree — i.e. for those twelve the fix has no measurable marginal effect right now.

That is the suite reporting honestly, **not** a defect in the suite, and it is not evidence that
twelve controls have rotted. Deciding which of those two it is requires reading the cases, which
this measurement did not do. Do not carry it forward as a finding without that reading.

## State of the row

`c79462050be4` is **not** closed by this. One of its two halves has a named, reproducible failure
(M7) and the other is unmeasured. The row stays open with this number attached.
