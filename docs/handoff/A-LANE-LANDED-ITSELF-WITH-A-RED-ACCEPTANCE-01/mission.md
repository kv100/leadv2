# A-LANE-LANDED-ITSELF-WITH-A-RED-ACCEPTANCE-01 (row `1fdca3ca1997`)

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**This row is the safety interlock for an unattended fleet** (founder decision 2026-09-17: a
24/7 lead session lands work on the VPS with no human reading each close). Today a human lead
catches a lane that lands itself red. With the fleet there is no such reader, so this defect
stops being an annoyance and becomes the mechanism by which red code reaches `main` at fleet
scale. Build it as an interlock, not as a patch.

## The evidence

Row `55de339ac133` (`LANE-LIVENESS-E0-GUARD-FIXTURE-COLLAPSES-EVERY-CASE-01`) was dispatched
with an acceptance requiring **both** `test-lane-verdict-three-states` and
`test-lane-truth-batch-01` to exit 0.

At the lane's own HEAD `79d0986f` the second suite is **`rc=1 pass=15 fail=1`, verified four
times.** `product-close` merged the lane to `main` at `cc386114` regardless, and the lane's own
report states *"Left red: Nothing. Both suites green"*.

## Discriminate the mechanism before you fix anything

Two candidates, and the row does not settle which:

1. the acceptance command was **never run** at close, or
2. it ran, went red, and its **exit code was not gated on**.

These need different fixes, and the shape of the evidence tells them apart: if it never ran
there is no acceptance artifact at all for that close; if it ran ungated there is a red artifact
that nothing consumed. Find which, in the close path of
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, and **say which one it was in the
report with the line that proves it.** A fix that would work under either hypothesis is a fix
whose author did not know the cause.

## The invariant to install

A close may not reach `landed` while the acceptance command the lane was dispatched with exits
non-zero. Absence of a verdict is not a pass: a close where the acceptance did not run, could
not run, or produced no exit code must be refused with its own distinct reason, never merged.
Each of those silences gets its own name in the journal — a single catch-all reason makes the
next diagnosis impossible.

## Off limits

- Do not weaken, skip, or make optional any acceptance. The direction of this row is strictly
  more blocking, never less.
- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not widen `tests/known-red-suites.txt`. Founder ruled against it.
- `leadv2-active-registry.sh` and `leadv2-dispatch-code.sh` — another lane owns them this
  session (row `e0a3caf252c8`). Stay out.

## Controls — two claims, two negative controls, both RUN, both outputs pasted

1. **A red acceptance blocks the landing.** Drive a close whose acceptance exits non-zero and
   confirm it does not reach `landed`. Then revert your change and confirm the same harness
   *does* land — a control that cannot fail on the unfixed code proves nothing.
2. **A green acceptance still lands.** Same harness, acceptance exits 0, lane lands. This
   guards against turning a fail-open into a fail-closed that stops the board.

Apply each mutation inside the function body in the lane worktree, never a scratch copy. Assert
the mutation target string is present before running, so a control cannot rot into a permanent
green.

## Deliverable

`docs/handoff/A-LANE-LANDED-ITSELF-WITH-A-RED-ACCEPTANCE-01/report.md` naming which of the two
mechanisms it was and the evidence line, plus a guard suite
`plugins/leadv2/scripts/tests/test-close-blocks-on-red-acceptance.sh` pinning both claims.
State how CI selects it on a change to `leadv2-dispatch-product-close.sh`, with the output.
