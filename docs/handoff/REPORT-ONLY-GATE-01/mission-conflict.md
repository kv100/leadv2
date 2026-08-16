# MISSION — REPORT-ONLY-GATE-01: resolve one merge conflict and land the work

The feature is finished and green (8/8 + 5/5 red-first). Two rounds have now been spent not landing
it, and the last worker timed out. The only thing left is **one conflicted file in the working tree
of `~/Projects/leadv2`**:

```
UU plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
```

Everything else is already staged and clean: `leadv2-dispatch-code.sh`,
`lib/leadv2-report-deliverable.sh`, `tests/test-report-only-gate.sh`, `tests/run-core-offline.sh`,
and the report.

## What to do

1. Resolve the conflict in `leadv2-dispatch-product-close.sh`. Both sides matter: the incoming side
   carries the report-only deliverable gate, the other side is whatever landed on `main` under it
   (`bb400e9` merged `dd43801`, the GLM-first router recovery). **Keep both behaviours** — this is a
   textual conflict, not a design disagreement. If the two genuinely cannot coexist, stop and say so
   rather than picking one.
2. Run `plugins/leadv2/scripts/tests/run-core-offline.sh` and the new
   `plugins/leadv2/scripts/tests/test-report-only-gate.sh`. Both must be green *after* the
   resolution, not from the pre-conflict run.
3. Commit on `main` in `~/Projects/leadv2`. This is the plugin repo and the single source — the work
   is only real once it is committed there.

## Hard constraints
- **Never `reset --hard`, `clean`, or `stash` in this tree.** It is shared with three live repos and
  other sessions edit it concurrently. Re-`git diff` immediately before you `git add`.
- Do not touch `docs/leadv2/open-threads.md`.

## Deliverable
The resolved file committed, both suites green, and a one-paragraph note in
`docs/handoff/REPORT-ONLY-GATE-01/report.md` saying what each side of the conflict contributed.
End with DELIVERABLE_COMPLETE.
