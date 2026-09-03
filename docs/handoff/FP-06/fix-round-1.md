# FP-06 fix-round 1 — review FAIL: telemetry lies (Heavy-guarded)

FIRST STEP, mandatory: in your lane worktree run `git merge worktree-5aeaa8bb` —
it carries the FP-06 build (a20dc31 + c74ab6e). Fix on top.

Full review (fix ALL High + M2/M3 data-integrity mediums exactly as written):
.claude/worktrees/5aeaa8bb/docs/handoff/dispatch-5aeaa8bb/review-opus.md

Headlines:
- H1: after a route_fallback the telemetry row records the ORIGINAL arbiter pick, not the
  arm/model that actually ran. The row must reflect the FINAL executing arm+model (the same
  identity worker_spawned journals) — that is the entire value of the dataset for FP-04.
- H2: census — 5 of 7 model-selection terminal paths emit no telemetry row. Every terminal
  (win, no_work, dead, refused-after-selection, e2e_regression...) must emit exactly one
  row. Enumerate the terminal emit sites (the review lists them) and cover each; add a test
  asserting one-row-per-terminal for each path via stubs.
- M2: fields are packed space-delimited and into CSV without escaping — a value containing
  a space or '=' corrupts both. Sanitize/quote (CSV: quote fields; journal: strip/replace
  spaces in values).
- M3: CSV header write is TOCTOU under concurrent dispatch — write header+row atomically
  (flock or tempfile+append pattern already used elsewhere in the repo; reuse it).
Skip M1/L* (backlogged).

Re-run test-model-select-telemetry.sh + test-freepool-capability-floor.sh green; extend the
telemetry suite for H1 (fallback case asserts final model) and H2 (per-terminal rows) with a
RUN-red negative control (revert H1 -> fallback test fails). bash -n touched scripts.
Commit: fix(leadv2): FP-06 fix-round 1 — telemetry truth (final arm), full terminal census, safe packing.
Report: docs/handoff/FP-06/fix-round-1-report.md (max 200 words, raw tails), end DELIVERABLE_COMPLETE.
