verdict: APPROVE
next_action: continue

Design: scope the selfcheck gate to its charter — run only when a review/e2e arm is actually spent, and make report-only fall-through an enforced condition, not a comment.

- Gate at product-close:1832 ignores both kill-switches, so it fires in the exit-trap fixture that sets E2E_ON=REVIEW_ON=0.
- `-x`→`-f` lib edit is correct — keep it; suite-only bypass env var rejected as lying-green.

Full: architect.full.md
