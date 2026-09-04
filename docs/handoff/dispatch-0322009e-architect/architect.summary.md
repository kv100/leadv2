verdict: APPROVE
next_action: continue

Case (d) is red because leg (a) writes `.arm-exceptions-<day>` with no `LEADV2_STATE_ROOT` while leg (d) reads with one — GLOB class is never symlinked, so the split shows.

- Fix: drop the two reader-side overrides; add a writer/reader pairing pre-assert.
- Falsification: mutant-copy `run_case` harness per suite.
- Also: `_TODAY_UTC` unvalidated in broad-status.

Full: architect.full.md
