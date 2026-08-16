verdict: APPROVE
next_action: continue

Render findings into `review-gate.md` additively — every existing key stays byte-identical.

- Reuse the dedup TSV / `review-findings.json` already built above both write sites; emit a sidecar render TSV carrying arm + verifier verdict.
- Add first-line `summary:`, `verdict:`, counts on the pass path, and an indented capped `findings:` block (medium+, stated omission count, newline-sanitised desc).
- `reported>0 && rendered==0` → `findings_parse: failed`, never `findings: none`. Verdict logic untouched.

Full: architect.full.md
