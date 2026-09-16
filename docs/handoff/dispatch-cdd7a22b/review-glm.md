REVIEW_CODE_VERDICT: PASS_WITH_NITS
REVIEW_MISSION_VERDICT: PASS_WITH_NITS
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=4

**Verification evidence (all probes run this session, post-merge worktree `26647d0efbb6`):**

- Mission snapshot integrity: live `mission.md` SHA-256 = `5349ae5b…c8dc05`, matches the contract's stated hash.
- Lane suites, own runs: `test-arm-selection-cost-quota-telemetry-01.sh` → `SUMMARY pass=15 fail=0`; `test-arm-selection-decision-fixtures-01.sh` → `SUMMARY pass=44 fail=0` incl. "reverting the mutation restored the baseline byte-for-byte" (negative control live); `test-fable-is-priced-from-its-own-window.sh` → `SUMMARY: pass=12 fail=0`. All match the report's §10.2 table.
- Allow-listed suite still red on branch: `test-arm-capability-honoured.sh` → `PASS=2 FAIL=2`, rot line `mutation did not flip the outcome -- control is not falsifiable` — identical to the failure text quoted in the `known-red-suites.txt` entry. Exactly one new entry added, as round 3 required.
- The diff's key external claim (YAML-subset loader accepts only `[A-Za-z0-9_.-]+` keys, motivating the `.` separator) — verified: `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:284` and `:309` carry `re.match(r'^[A-Za-z0-9_.-]+$', k)`.
- The claim that two suites assert `price_ratio`'s exact string (justifying byte-identical preservation) — verified: `test-arbiter-decision-record-inputs.sh:54`, `test-exclusion-stages.sh:113,173`.
- New suite falsifiability probed with `leadv2-suite-falsifiable.sh`: `verdict: falsifiable — a failure injection turned the suite red (rc=1)`, `shim_invocations=1`.

**Correctness (lens 1):** The four changes are sound. `_price_key_candidates` most-specific-first with skip-not-zero semantics is right, and legacy sparse configs resolve through the last candidate unchanged (A2/A4 pin both halves). The `windows.pop('seven_day')` removal implements the founder's keep-both ruling; worst-of-readable-windows, never sum (fable C5a/C5b pin pricing-level worst-binds in both directions). The rotation filter degrades to byte-identical legacy behavior under `FIT_MODE != 'on'`. The print format string grew from 26 to 27 `%s` with a matching 27th argument (`_loser_detail_tok`) — counted, consistent. `'loser_detail':globals().get('_loser_detail')` is safe on early-refuse rows.

**Findings:**

1. **Medium — mission_alignment** `docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md:781` — §10.4's last bullet promises "verdict recorded in §10.5 below", but the file ends at §10.4; no §10.5 exists (781 lines total, tail verified). Round 4's core deliverable is a recorded review verdict for this diff; the report dangles a pointer to a section that was never written. (This review itself partially supplies the missing verdict, but the report should either write §10.5 or drop the reference.)

2. **Low — tests-can-fail (census, all same-shape instances enumerated)** `plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh` — all 14 assertion sites in A1, A2, A3, A4, B1, B2, C1, C2, D1 (winner check, 3× arm_excluded loop, loser_detail presence + 3 token checks), D2 use bash-native `[[ == *…* ]]` compares, the exact shape commit `ce86d4ed` removed from the fable suite because the falsifiability shim cannot touch them. The suite currently passes the gate solely via D1's single `grep -o` (measured `shim_invocations=1`); deleting that one grep flips the checker to `suite_not_falsifiable`. Not blocking — assertions do fail on wrong output — but it is one edit away from the exact refusal that blocked round 2.

3. **Low — correctness (comment)** `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:614` — comment says the subset loader is ":421 below"; the key regex actually lives at `:284`/`:309`, *above* the comment. Stale direction/line.

4. **Low — tests** `test-arm-selection-cost-quota-telemetry-01.sh:450` (B1) — first assertion pattern `'"fable": "capped"'` (spaced-JSON shape) can never match the stdout decision line; the assertion survives on the loose fallback `*'fable:'*'capped'*`. Dead pattern arm.

5. **Low — mission_alignment (observation)** §5 vocabulary: only 3 of the 10 mission tokens (`insufficient_fit`, `cost_unknown`, `higher_expected_cost`) appear as new `loser_detail` reasons; the rest rely on pre-existing stage names. The round-2 lead brief explicitly endorsed this shape, so it is accepted-by-mission — noting only for the record.

No Critical/High findings. No stash created; no files changed by this review.

FINISH CONTRACT: files changed by reviewer — none. Test results (own runs, honest): telemetry 15/0 rc-pass, fixtures 44/0, fable 12/0, arm-capability-honoured red (PASS=2 FAIL=2, expected/pre-existing), falsifiability checker verdict=falsifiable. Commit: NOT-COMMITTED — review-only session; the reviewed diff belongs to the lane-worker, and no review artefact was requested to be committed.
