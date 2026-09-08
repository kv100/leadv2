LABEL=critic-dispatch-98777feb-review-1788862694 SESSION_ID=aad9ccc3-5cfd-4c6b-ab39-8a59551329b9
--- body from: docs/handoff/dispatch-98777feb-review/critic.full.md ---
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=0 low=2

## Scope
Diff reviewed: `docs/handoff/dispatch-98777feb/review.diff` — `run-core-offline.sh`'s
`_core_offline_scope_changed_select()` empty-diff path, plus
`test-core-offline-scope-changed.sh` (updated) and
`test-scope-empty-lane-is-not-a-full-run.sh` (new).

## Correctness (verified, no issues)
- Per-call state reset: `SCOPE_SELECTED_DEFS=()` and all `SCOPE_*` vars are
  reinitialized at the top of every call, so the new empty-diff early-return
  (`SCOPE_SELECTION_REASON="no_relevant_changed_files"; return 0`) cannot
  leak stale state from a prior invocation.
- Verdict branching is correctly scoped: only `reason == "no_relevant_changed_files"`
  maps to the new `nothing_to_run` short-circuit (exit 0, zero suites). The
  `unmapped_files` path is untouched — still `return 1` /
  `full_set_fallback`, preserving fail-open for genuinely uncertain coverage.
- `LEADV2_CORE_OFFLINE_SCOPE_DUMP` introspection check remains ordered before
  the new short-circuit, so dump-mode behavior is unaffected.
- New `verdict=`/`reason=` fields inserted into `SCOPE_RESULT` and the new
  short-circuit's own "suites passed=0 failed=0 missing=0 verdict=... reason=..."
  line do not break any parser in-repo: no non-test script greps these lines
  (`grep -rn "suites passed=" plugins/leadv2/scripts --include="*.sh"` outside
  tests/run-core-offline.sh and tests/test-*.sh returns nothing), and both
  consuming test files (`test-core-offline-scope-changed.sh`'s
  `executed_from()`/`scope_field()`, `test-scope-excludes-nested-housekeeping.sh`
  line 66) use wildcard-tolerant `sed`/`grep -o` patterns unaffected by
  additional fields.
- Checked the one pre-existing, out-of-diff sibling test that also parses
  this log line, `test-scope-excludes-nested-housekeeping.sh`, in full: its
  three cases (`nested_housekeeping_case`, `genuine_unmapped_still_fallback_case`,
  `registration_case`) all construct a fixture with a real changed source
  file (`greeble.sh`) — none of them exercises a docs-only/empty
  relevant-changed-file diff. This diff's new `nothing_to_run` behavior is
  therefore never reached by that suite; it is unaffected, not silently
  broken.
- The rewritten `clean_case()` in `test-core-offline-scope-changed.sh`
  correctly asserts the new contract (`rc==0`, `executed==0`, `selected==0`,
  `verdict==nothing_to_run`, `reason` contains `no_relevant_changed_files`).
- New `test-scope-empty-lane-is-not-a-full-run.sh`: fixture setup (fresh
  branch, docs-only commit) correctly exercises both the dump-mode and
  actual-execution empty-diff paths, and separately re-proves the unmapped
  fail-open path (untracked and staged) is unchanged (`selected==TOTAL`,
  `reason=unmapped_files`). Sound coverage of the diff's stated intent.

## Findings

### Low — misleading "negative controls" comment in the new test file
`test-scope-empty-lane-is-not-a-full-run.sh`'s header claims negative controls
"target the empty return and unmapped return INSIDE
`_core_offline_scope_changed_select` via `leadv2-mutation-control.sh`", but
the script body never invokes `leadv2-mutation-control.sh` — its actual
"controls" are git-fixture-state variations (docs-only vs. genuine uncovered
source), not mutation testing. This reads as boilerplate copied from
`run-core-offline.sh`'s own header (which does describe real
`leadv2-mutation-control.sh`-based controls for the unrelated `scope-mut-1`/
`scope-mut-2` markers, driven by a separate out-of-scope DOD-gate mechanism).
Not a functional defect — the test's actual assertions are correct and
sufficient — but the comment overstates the rigor applied and should be
corrected to describe what the file actually does (fixture-state variation,
not mutation proof).

### Low — two divergent "suites passed=" line formats (forward risk only)
The pre-existing completion line (`run-core-offline.sh:1103`,
`suites passed=%d failed=%d missing=%d repo=%s`) and the new short-circuit
line (`... verdict=%s reason=%s repo=%s`) now coexist with different field
sets for the same log prefix. Confirmed harmless today (see Correctness
above — both consumers use tolerant wildcard patterns), but it's a latent
trap for a future test author who writes a strict positional parser against
one variant and gets silently wrong results against the other. No action
required for this diff; worth a one-line note if a follow-up ever touches
this log line again.

## Verdict rationale
No Critical or High findings: the core logic change is correct, fail-open
for uncertain coverage is preserved, no existing parser or sibling test is
broken. Two Low findings (comment accuracy, latent format-divergence risk)
keep this at PASS_WITH_NITS rather than a clean PASS.

DELIVERABLE_COMPLETE
