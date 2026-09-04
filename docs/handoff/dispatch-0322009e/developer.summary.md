verdict: REVISE
next_action: review_round_2

Ladder suite green; census-corrected the design's root cause (state-root pairing wasn't the bug). Falsification markers added to all three suites, real-mutant-verified.

- Root cause of leg (d) was misdiagnosed by the prepass: it was already red at merge-base aed1f2b, before any state-path change — fixed by pointing the assertion at founder-status-full.md (where provider-health lines actually render; compact founder-status.md hides them unconditionally by design).
- Added a §3 `_TODAY_UTC` malformed-date guard in leadv2-broad-status.sh.
- Three new suites now carry real RED-then-GREEN falsification (genuine mutants, not printed markers).
- run-core-offline.sh: 57 passed / 3 failed — the 3 failures (relay-scope, fanout guard, lane-truth-batch) are pre-existing regressions unrelated to my changes (confirmed red at merge-base baseline vs my untouched files); reported, not fixed (out of scope).
- `test-broad-status-lanes-blind.sh` named in the mission does not exist in this tree.

Full: full.md
