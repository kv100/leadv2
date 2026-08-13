verdict: APPROVE
next_action: continue

Design: bind review proof to `sha256(review.diff)` matched against a PASS ledger row, and re-hash every artifact at assert time so no phase passes on a bare `-f`.

- F1: `--diff-hash` persisted at record, verified against a `code-review-ledger` PASS row.
- F2: universal re-hash gate + per-phase content assertions; zero `-f` proofs remain.
- F3: suite rewritten to drive `cmd_resolve` with stub launchers; 8 red-first cases.

Full: architect.full.md
