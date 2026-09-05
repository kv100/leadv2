# FP-07b — review body-lost retry finds no candidate: pool parse shape mismatch (P2, Light)

Repo: canonical leadv2 plugin. Context: docs/leadv2/freepool-backlog.md §FP-07b.

Bug (live, 2026-08-28, FP-03 review): FP-07's `_review_next_distinct_ok_arm` in
plugins/leadv2/scripts/leadv2-review-run.sh never fires because the pool variable it
filters is EMPTY. Root cause: the pool resolver `lib/leadv2-glm-policy-resolve.py` output
is parsed expecting `reviewer=`/`pool=` tokens, but the resolver actually prints
`arm=`/`rule=` lines — so the engine's parsed pool is empty and the retry has no
candidates. The primary review still works via a different path; only the retry pool is
starved.

Fix:
1. Align the parse with the resolver's REAL output (or make the resolver additionally
   emit `pool=` — pick the smaller, single-owner change; do not duplicate the pool in
   two formats). The distinct-arm retry must receive the same quota-filtered,
   author-excluded arm list the primary selection used.
2. Regression test (plugins/leadv2/scripts/tests/): drive the retry path with the REAL
   resolver output format (captured fixture, not a hand-typed stub) -> retry must pick a
   distinct arm. Negative control declared in the suite header and RUN red (mutation:
   revert the parse to the wrong token -> test must fail). Extend the existing
   test-review-body-lost-retry-distinct-arm.sh rather than adding a parallel suite.
Run the touched suite + bash -n; raw output in report.

Commit: fix(leadv2): FP-07b review retry pool parse matches resolver output.
Report: docs/handoff/FP-07b/report.md (max 200 words), end DELIVERABLE_COMPLETE.
