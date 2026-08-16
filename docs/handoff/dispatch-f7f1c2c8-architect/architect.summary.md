verdict: APPROVE
next_action: continue

# architect — REPORT-ONLY-GATE-01

Both conflict sides are orthogonal and must both be kept: take the incoming report/diff `if`,
give both arms HEAD's findings-append + tmp/mv write.

- Case 4 golden-compares vs `git archive HEAD` — dropping HEAD's side fails it.
- Cases 1–3 use line-anchored greps — appending to the report arm is safe.
- One hunk, one file; hoist `_rgf_rel` / `_rgf_dnm` above the `if`.

Full: architect.full.md
