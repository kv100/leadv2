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

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e1854c51" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.