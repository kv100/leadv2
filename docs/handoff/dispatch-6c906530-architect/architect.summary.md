verdict: APPROVE
next_action: continue

Design scopes F1/F2/F3 only; all three reproduce verbatim at `b29f9b2`.

- F1: canonical diff-hash = `sha256(docs/handoff/dispatch-<sig8>/review.diff)` (product-close:1488); join to `code-review-ledger` rows requiring PASS/PASS_WITH_NITS.
- F2: `_artifact_integrity` re-hash for all five; build=non-empty lane diff, deploy=ancestor-of-origin/main (additive `commit:` field); test/live_verify/e2e integrity-only.
- F3: append G1–G6 driving `dispatch-code.sh` via the `test-landed-at-spawn.sh` stub harness, red-first vs `5ba7620`.
- CRITICAL out-of-scope: `dispatch-code.sh:2479` hardcodes `"worktree-d4d014e1"` — lead ruling needed.

Full: architect.full.md
