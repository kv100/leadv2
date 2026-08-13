verdict: REVISE
next_action: continue

Not a flake: the suite's two blocks run against different trees (live vs `git archive HEAD`), so pre-fix `FAIL C5` is required red-first evidence.

- Verified live: post-fix 5/5, exit 0, C3 green both blocks.
- Fix is harness labelling only — no product-code change.
- Writes: `test-lane-diff-single-repo.sh`.

Full: architect.full.md
