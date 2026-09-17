# DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01

Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. Read them first.

**This row is a precondition for an unattended fleet** (founder decision 2026-09-17: a 24/7
lead session with a lane cap runs the WAVES.md board on the VPS). Without this fix the board
is serialised to roughly four lane starts per hour no matter how many agents exist, so the
fleet is a queue rather than a fleet. Treat the concurrency proof as the deliverable, not the
one-line write.

## The defect, precisely

Measured 2026-09-17. Six lanes were dispatched, each with an explicit `--writes` on its
command line. **Five of six recorded `writes: None` in `active.yaml`.** The one that did
record it was the one dispatched alone; the six staggered ~20s apart did not. That shape —
correct when serial, lost when concurrent — is a last-writer-wins race on `active.yaml`,
not a missing argument.

The consequence is board-wide, and this is why the row matters more than its size suggests:
`leadv2-active-registry.sh:564` refuses a row whose write set is unrecorded with
`reason=pending_resolution` **before any path comparison happens**. So a single lane with a
lost write set blocks *every* new dispatch for the full 900s window, whether or not any path
overlaps. Measured the same day: 6 of 8 live rows carried `writes: ABSENT`, one of them 20
minutes old.

## Where the fix must and must not go

**The writer is the defect.** Fix the persistence so a concurrent registration cannot lose
the field — read-modify-write under the registry's own lock, or an append/merge that does not
rewrite a sibling's row.

**Do not touch the reader's refusal.** Making `:564` stop refusing on an unrecorded set would
turn a board-wide stall into silent write-set collisions between lanes — a fail-open on the
one gate that keeps two lanes off the same file. An unrecorded set must keep meaning "refuse".
The fix makes sets recorded; it does not make unrecorded sets acceptable.

## Off limits

- `leadv2-dispatch-product-close.sh` — another lane owns it this session.
- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`.
- Do not widen `tests/known-red-suites.txt`. Founder ruled against it.

## Controls — two claims, two negative controls, both RUN, both outputs pasted

1. **Concurrent dispatch records every write set.** Register N≥5 rows within a few seconds,
   each with a distinct `--writes`, and assert all N read back their own set. Then revert your
   change and confirm the same harness loses at least one — a control that cannot fail on the
   unfixed code proves nothing.
2. **An unrecorded set still refuses.** Force one row to have no write set and confirm the
   admission gate still refuses `pending_resolution`. This is the fail-open guard; prove it,
   do not assert it.

Apply each mutation inside the function body in the lane worktree, never a scratch copy.
Assert the mutation target string is present before running, so a control cannot rot into a
permanent green.

## Deliverable

`docs/handoff/DISPATCHER-DOES-NOT-PERSIST-WRITES-INTO-THE-REGISTRY-ROW-01/report.md`, plus a
guard suite `plugins/leadv2/scripts/tests/test-writes-persist-under-concurrency.sh` pinning
both claims above. State in the report how CI selects that suite on a change to the writer
file, with the selection output.
