# T13-SLICE2-NEGATIVE-CONTROL-MUTATES-A-CLAUSE-THAT-NO-LONGER-EXISTS-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## One red suite, one case, and it is the control itself that is broken

`plugins/leadv2/scripts/tests/test-t13-slice2.sh` — rc=1, PASS=14 FAIL=1.

```
[TEST] FAIL: NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) unexpectedly still passed
```

Observed mechanism: the control at `test-t13-slice2.sh:97` builds its mutant with

```
sed 's/ and (allowed is None or c\.get(.arm.) in allowed)//'
```

That clause **no longer exists** in the subject — a grep for it returns no match. The real
`allowed_arms` filter now lives at `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1306`:

```
if allowed is not None: return arm in allowed
```

So the sed is a no-op copy, the "mutated" arbiter is byte-identical to the real one, and it
naturally reproduces case 1. The suite is red because its own negative control rotted when the
subject was refactored — not because the arbiter regressed.

This is the mirror of the failure mode the lane rules warn about: a control whose mutation target
has drifted proves nothing, whichever colour it happens to land on.

## What to do

1. Re-run the suite and confirm the above before changing anything.
2. Re-point the control at the clause that actually implements the filter today
   (`leadv2-route-arbiter.sh:1306`), so the mutant really loses the `allowed_arms` behaviour.
3. Make the control **self-checking**: it must fail loudly if its mutation target is absent, so
   the next refactor cannot silently turn it back into a no-op. A control that cannot bite must
   say so rather than report a colour.
4. Then confirm the mutated arbiter fails case 1 and the unmutated one passes it, and paste both.

## Off limits

- Do not change `leadv2-route-arbiter.sh` behaviour. The arbiter is not the defect here; the
  control's mutation target is. If you come to believe the arbiter is wrong, stop and say so in
  the report with your evidence rather than editing it.
- Never make the suite green by deleting the control, weakening its assertion, or adding
  `|| true`. Deleting the control would "fix" the suite and destroy the thing it exists for.

## Control

One claim, one negative control, run, both outputs pasted. Apply the mutation inside the function
body in the lane worktree — not in a scratch copy: this suite family was measured to give
different results in a detached worktree than in a registered lane worktree at the same commit.
Assert the mutation target is present before running.

## Deliverable

`docs/handoff/T13-SLICE2-NEGATIVE-CONTROL-MUTATES-A-CLAUSE-THAT-NO-LONGER-EXISTS-01/report.md` —
before/after counts with their boundary (counts, ceiling, platform, commit), the re-pointed
control with both outputs, and a one-line statement of how the control now detects its own
target going missing.
