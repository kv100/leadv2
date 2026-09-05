[provider-quota-gate] OK — codex 71% < 95%
# Codex Adversarial Review

Target: branch diff against HEAD
Verdict: needs-attention

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=6 medium=0 low=0
No ship: the new CI gate can report green without a complete, trustworthy test run.

Findings:
- [high] tests/ci-gate.sh:59 fail-opens wrapper failures (tests/ci-gate.sh:59-74)
  Because the wrapper path is unconditionally skipped and only `RUN_RC == 2` is fatal, a `run-core-offline.sh` crash or lock timeout with no parsed failure label leaves `UNEXPECTED` empty and passes CI; make every unreconciled nonzero wrapper exit blocking.
  Recommendation: Fail for any nonzero run-all exit unless structured output proves every failure was allow-listed.
- [high] tests/run-all.sh:487 masks mixed fatal runs (tests/run-all.sh:487-503)
  Once any parsed core failure is allow-listed, a later missing-suite or other unparsed wrapper fatal still sets `classified=1` and suppresses `[FAIL]`, allowing CI to pass after an incomplete test run; require an explicit successful wrapper completion signal before accepting known-red classification.
  Recommendation: Classify only a structured complete result and fail on all MISSING or fatal wrapper conditions.
- [high] tests/known-red-guard.sh:45 permits allow-list substitution (tests/known-red-guard.sh:45-62)
  Comparing only entry counts lets a change replace an existing allow-listed ID with a newly failing suite at the same count, concealing a regression while satisfying the claimed shrink-only policy; normalize entries and require the current set to be a subset of the base set.
  Recommendation: Compare normalized allow-list identities rather than counts.
- [high] .github/workflows/test-suites.yml:18 selects an incompatible runner (.github/workflows/test-suites.yml:18-25)
  The changed-scope Ubuntu job runs the changed lane-watch suite, whose fixture uses macOS-only `date -v` and `/usr/bin/SetFile`, so this diff makes its own CI path fail rather than test the change; run that suite on macOS or make its fixtures portable and explicitly skip unsupported cases.
  Recommendation: Split the lane-watch suite onto macOS or replace its macOS-only time and birth-time operations.
- [high] leadv2-loop-detect.py:289 can hang every tool hook (plugins/leadv2/scripts/leadv2-loop-detect.py:289-299)
  With `LEADV2_TOOL_FREQ_WARN=0`, the new anchor loop keeps multiplying zero while it remains below the hard limit, so detector import never returns and every PreToolUse hook times out; reject non-positive thresholds or return an empty anchor set.
  Recommendation: Validate both thresholds before calculating anchors and handle disabled warnings without looping.
- [high] leadv2-dispatch-code.sh:6923 treats lost state as fresh bootstrap (plugins/leadv2/scripts/leadv2-dispatch-code.sh:6923-6943)
  A previously dispatched task with a deleted or unavailable phase store is indistinguishable from a fresh zero-record lane and is admitted before the subsequent classify write is silently ignored, bypassing required plan and gate1 evidence; bind bootstrap to durable task provenance and fail closed if classification cannot persist.
  Recommendation: Use an immutable first-dispatch marker and make the post-admission classify write mandatory.

Next steps:
- Fix the CI fail-open paths before relying on this workflow for merge protection.
- Add negative tests for zero thresholds, mixed wrapper fatal output, and lost phase state.
