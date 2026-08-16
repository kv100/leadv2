verdict: APPROVE
next_action: continue

Design: a mission-declared `LANE_DELIVERABLE: report:<path>` gives the close gate a report branch, so a finished analysis stops reading as `no_work`.

- New shared lib parses/validates/harvests the report to ROOT; report lanes bypass the diff predicate, code lanes untouched.
- Report is reviewed through the existing review path (body substituted, prose rubric), not skipped.
- `review-gate.md` gains `kind:` — report vs dead worker distinguishable.

Full: architect.full.md
