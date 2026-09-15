# DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01 — round 2

Round 1 is **accepted on its own terms**: `test-dispatch-refusal-truth.sh` is 6/0, the three
refusal causes now name themselves, and the report was honest that the aggregate runner was RED
rather than dressing it up. Keep all of that. Continue in this worktree; do not restart.

This round is one finding, found by the lead reading the round-1 diff.

## The finding — the caller migration picked the slowest possible kind
Round 1 discovered legacy test callers using the invalid spellings `--kind code` / `--kind safety`
and migrated them. Measured in the round-1 diff: they were migrated to **`--kind product`** —
3+3+2+2 occurrences and more across 33 changed files.

`product` is the one kind that is **not** in the non-product set. From the dispatcher itself:

```
leadv2-dispatch-code.sh:4363
LEADV2_NON_PRODUCT_KINDS="plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation"
```

Anything outside that set classifies as `product / conservative_default`, which is what triggers
the architect prepass — default budget `LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC=420s`. So every
migrated fixture that actually dispatches now pays a 420s prepass it did not pay before.

Round 1's own evidence is consistent with that: after the migration the aggregate runner blew the
60-second per-suite ceiling and exited 124.

```
[CORE-OFFLINE] scope=changed running 161 of 93 suites (base=main@5da9324f27, 33 changed files, 0 unmapped)
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 60s ceiling
exit 124
```

A test fixture is tooling. Routing it through the product prepass is not a fix for an invalid
kind — it is a new tax on every suite that was touched, and this repo is already paying a
measured tax for slow and red suites.

## What to do
For each caller migrated in round 1, choose the kind by **what the test is**, not by what is
shortest to type:

- The fixture merely needs *a valid kind* so the dispatcher proceeds → use a non-product kind from
  the set above (`tooling` for a test fixture unless something fits better).
- The test's **subject** is specifically the product path / the prepass / `conservative_default`
  behaviour → `product` is correct and it stays. Name each such case and say why.

Callers carrying `--no-spawn` never reach the prepass at all; say so rather than assuming, and do
not change one just to be tidy if the change has no effect — a diff with no effect still has to be
reviewed.

## Then re-measure, same instrument both times
Run the changed-scope runner **at the same ceiling** before and after this round's change and
report both numbers with their boundary: how many suites selected, how many ran, how many red,
what ceiling, on which platform. A single "after" number proves nothing about a delta.

If the runner is still red after the change, that is a **result, not a failure** — report it with
the cause. Do not raise the ceiling to make it pass: the ceiling is the instrument, and moving the
instrument to get the reading you want destroys the measurement.

## Do not weaken anything
- Round 1's six refusal-truth assertions stay exactly as they are.
- Do not delete an assertion, loosen a grep, or add `|| true` to make a suite green.
- `2>/dev/null` hides an error so it reads exactly like success — do not add any, and say so if
  you find one in the path you touch.

## Negative control — RUN it
Restore `--kind product` in one migrated fixture that does reach the prepass, show the suite's
wall-clock jump (or its timeout) against the same ceiling, restore. Paste both timings. This is a
performance claim, so the control must be a timing, not a pass/fail.

If you find that no migrated fixture actually reaches the prepass — that the whole finding is
wrong — **say that plainly with the evidence and change nothing.** A falsified premise reported
cleanly is a complete round; round 1 already did exactly that on its own hypothesis and it was the
right call.

## Off limits
- The refusal-cause fix itself (`D1`/`D2`/`D3`) — settled in round 1.
- `LEADV2_NON_PRODUCT_KINDS` and the prepass timeout value: this round picks the right kind at the
  call sites, it does not redefine the sets or the budget.
- Do not `git stash`, `git reset --hard` or `git clean` — this checkout is shared with live
  sessions in three other repos.

## Report
Append `## Round 2` to `docs/handoff/DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01/report.md`: the
per-caller kind decision (and the ones deliberately left as `product`, with the reason), the
before/after runner measurement with its boundary, and the timing control.
End with `DELIVERABLE_COMPLETE`.
