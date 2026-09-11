verdict: APPROVE
next_action: review_round_2

Fixed both standing-red test suites (test-only, no production script touched).

- R1: `no_plugin_leak` guard in test-leadv2-route-bandit.sh now checks for this test's own `TEST-SELECT-03/route-decisions.yaml` artifact instead of the (git-tracked, legitimately-existing) `docs/handoff` dir.
- R2: Test 7 in test-leadv2-phase8-learn-counter.sh now normalizes `tmp_unrelated` via `cd && pwd` before comparing, matching how `r_unrelated` was produced — fixes the double-slash TMPDIR mismatch.

Full: developer.full.md
