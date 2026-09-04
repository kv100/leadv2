verdict: APPROVE
next_action: review_round_2

Closed both control gaps in test-codex-broker-staleness.sh: added case 1b (live/reused pid + swept sessionDir) and case 4 (death-report enrichment), both mutation-proven RED/GREEN.

- Case 1b proves sessionDir presence is load-bearing independent of pid liveness (the exact reused-pid scenario the brief named); mutating `-d "$_session_dir"` away turns it red.
- Case 4 asserts lastLogLine/brokerAgeSec/brokerSessionDirPresent on the persisted job record via a brace-aware Python extractor (plain sed breaks on the heredoc's unindented `}`); blanking deathDiagnostics turns it red.
- Full suite: pass=5 fail=0. Committed 90cbd7a. `tests/run-all.sh --scope changed` queued 30+min behind 60+ waiters on a shared offline-test lock from ~11 concurrently active lanes — environmental, not from this diff.

Full: developer.full.md
