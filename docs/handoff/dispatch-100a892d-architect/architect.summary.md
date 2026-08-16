verdict: REVISE
next_action: continue

Mission premise wrong: routing config and author-exclusion already work. `.claude/scripts/` is a stale script copy the dispatch ran from — one root cause for all three symptoms.

- Symlink 6 dispatch-path files; add tenant routing yaml; refuse stale trees loudly.
- review-run.sh discards resolver rc/stderr — restore.
- phase-record: load-bearing, not noise.

Full: architect.full.md
