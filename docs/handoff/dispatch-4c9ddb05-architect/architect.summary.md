verdict: APPROVE
next_action: continue

Design: one shared renderer (`leadv2-review-findings.sh`) appends a findings block to review-gate.md.

- **Live gate writer is `leadv2-dispatch-product-close.sh:2037/2045`, not review-run.sh** — all three real gates lack its `arms:` line. Both must render.
- Real reports carry no `FINDING:` lines → markdown-section extractor; parse failure degrades to `findings: unavailable` + pointer.
- `reviewer_says: do_not_merge` advisory; verdicts/exit codes unchanged.

Full: architect.full.md
