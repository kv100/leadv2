# GATE-FALSE-SILENT-01 — decision on test-lane-diff-single-repo.sh Case C5

DECISION_OPTION: a
RATIONALE: C5 encodes the exact defect the fix removes, so it is a stale spec-mirror of Case 1, not an independent regression — re-author it under the same treatment and proceed.

## What discovery establishes (verified in-tree)

`plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh:181-203`
(`case_c5_registered_arm_silent`) builds a clean lane, writes
`docs/handoff/dispatch-c5sig001/arm-registered` (`arm=sonnet handle=PID=0 epoch=0`),
never creates a stream file, and passes only when the gate emits
`terminal=no_work` **and** `cause=arm_produced_nothing` (line 198).

That is Defect 2 verbatim: an **absent** stream treated as positive evidence of a
silent arm. The fix's whole point is that absence is not evidence. So C5's assertion
and the fix's specification are mutually exclusive by construction — one of the two
must change; there is no implementation that satisfies both.

## Why this is not a real regression

A regression is behaviour the system was supposed to keep and lost. C5 is a test
whose *oracle* is the bug. It is the same artifact as Case 1 in
`test-dispatch-silent-arm.sh`, which the design already approved for re-authoring;
the design's off-limits census simply enumerated one instance of that class and
missed the second. The census was incomplete, not restrictive: nothing in it forbids
touching `test-lane-diff-single-repo.sh`. Holding on an incomplete enumeration would
freeze the fix on a clerical omission.

The red-first evidence (green on pre-fix HEAD, red on the fix, via
`run-core-offline.sh`'s dual-pass harness) is exactly the signature of an
intentional-behaviour-change test, and is the strongest argument *for* re-authoring:
it proves C5 is measuring the changed axis and nothing else.

## Constraints on the re-authoring (binding on the implementer)

1. **Do not merely negate.** `! grep -q cause=arm_produced_nothing` passes on a gate
   crash, an empty stderr, or any unrelated failure — a vacuous oracle. The
   re-authored C5 must assert the *positive* corrected outcome (the specific
   terminal/cause the fix now emits for registered-arm + absent-stream), matching
   whatever Case 1 asserts. Case 1 is the reference spelling; keep them textually
   parallel so the next census cannot miss one again.
2. **Keep the case, keep the name.** Do not delete C5 and do not rename it. The
   registered-arm + absent-stream path is precisely the path this fix changes and
   must stay covered; deleting it converts a caught regression into a blind spot.
3. **Amend the off-limits census in the same commit.** Add
   `test-lane-diff-single-repo.sh` Case C5 alongside `test-dispatch-silent-arm.sh`
   Case 1 in the design's re-authoring list, so the record shows two instances of the
   class, not one. This is the actual defect the question surfaced.
4. **Re-run the dual-pass harness after re-authoring**: the suite must be red on
   pre-fix HEAD and green on the fix — the inverse of today. If it is green on both,
   the new assertion is vacuous (see 1) and must be tightened before landing.

## Risks

| Risk | Mitigation |
|---|---|
| Vacuous re-author (negation-only oracle) hides a future re-introduction of Defect 2 | Constraint 1: assert the positive cause, mirror Case 1's spelling |
| A third stale test elsewhere asserts the same old behaviour and is still unfound | Before landing, grep the whole `tests/` tree for `arm_produced_nothing` and re-author every occurrence whose fixture has no stream file |
| Census stays incomplete, so the next fix in this area repeats the surprise | Constraint 3: amend the census in the same commit |

## Out of scope

- Implementing the fix or the re-authored case (decide-only mission).
- Any change to gate semantics beyond what GATE-FALSE-SILENT-01 already specifies.
- The `.claude/scripts/tests/` duplication thread (separate blast radius).

DECISION_OPTION: a
RATIONALE: C5 asserts the defect being fixed, so it is a stale spec-mirror of Case 1 — re-author it identically and proceed.

DELIVERABLE_COMPLETE
