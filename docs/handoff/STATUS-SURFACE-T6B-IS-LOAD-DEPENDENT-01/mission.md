# STATUS-SURFACE-T6B-IS-LOAD-DEPENDENT-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

## The defect, observed

`_t6b` in `tests/test-status-surface-bash32.sh` (repo-root `tests/`, NOT `plugins/leadv2/scripts/tests/`) takes **two independent
live renders** of the status surface — one under a minimal environment, one full — and asserts
that their lane-row counts are equal.

Nothing holds the board still between the two captures. On 2026-09-16, with three lanes live, it
read `min=2 full=3` and the lane was killed with a false `terminal=dead cause=e2e_regression`
(lane `81aeab93`).

The paired measurement is what settles it: with the board quiet the case is **green on both the
merge base `9e75594b` and the lane branch**. So this is not a regression the lane introduced. It
is a criterion demanding a **load-independent outcome from a load-dependent measurement** — it
fails as a function of how many lanes happen to be alive, which is not a property of the code
under test.

The rest of the suite is sound: 14 of 15 cases pass, and it is the only suite carrying
**bash-3.2 coverage**. That coverage must survive whatever you do.

## What a fix must be, and what it must not be

The case is asserting something real — that the two render paths agree — and that assertion
should survive. What must go is the dependence on wall-clock board state. Two shapes are
plausible:

- **Freeze the input.** Both renders read ONE captured lane set (a fixture, or a single snapshot
  taken once and fed to both invocations), so the comparison is between two renderers over
  identical input rather than between two moments in time.
- **Compare something that cannot change between captures.** If a stable projection of the render
  exists that is invariant to how many lanes are live, assert on that instead.

Prefer the first if both are available: it keeps the case testing what it was written to test.
State which you chose and name what you rejected.

**What is not acceptable:** deleting `_t6b`, marking it skipped, adding a retry loop until the
counts agree, or asserting `min <= full`. A retry hides the same flake behind a longer wait, and
an inequality is a weaker claim dressed as a fix. If you conclude the case cannot be made
deterministic, say so explicitly with the reasoning and leave it red and named — that is allowed;
silently weakening it is not.

## Off limits

- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not drop the bash-3.2 coverage. If your change uses any bash-4 construct the suite stops
  testing the thing it exists for — check, and say in the report that you checked.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
  `leadv2-active-registry.sh`, `leadv2-route-arbiter.sh` or `leadv2-dispatch-product-close.sh` —
  other lanes hold all four.

## Controls

Two independent claims, two negative controls, each RUN, both outputs pasted:

1. **The case is now load-independent.** Run `_t6b` while the board is busy — dispatch nothing,
   but arrange the lane set the renders read to differ between the two captures if your fix were
   absent (the simplest form: revert your change, reproduce the disagreement, restore it). The
   control is: with the fix the case is green under a changing board; without it, red.
2. **The case still detects a genuine renderer disagreement.** Mutate the renderer inside the
   function body so the two paths really do disagree, and confirm `_t6b` goes red. A case that
   stops being able to fail is not a fix — it is the flake removed by removing the test.

Apply each mutation **inside the function body in the lane worktree**, never a scratch copy.
Assert the mutation target string is present before running, so a control cannot rot into a
permanent green.

Also paste the rc and the pass/fail counts of the **whole** suite before and after, so the
14-of-15 baseline is visible and it is clear nothing else moved.

## Deliverable

`docs/handoff/STATUS-SURFACE-T6B-IS-LOAD-DEPENDENT-01/report.md` — the chosen shape with the
rejected alternative named, whole-suite counts before/after with their boundary (counts, ceiling,
platform, commit), explicit confirmation that bash-3.2 coverage is intact and how you checked,
and both controls with pasted output.
