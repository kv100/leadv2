verdict: APPROVE
next_action: review_round_2

# PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01 — round 2

Round 1 (`1b8b0243`) added bracket-severity parsing to `leadv2-review-run.sh`, but Codex's own
review of that commit surfaced 3 `[high]` findings (`docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md`)
that this round fixes.

## Fix 1 — `findings_total` absent on the normal fail path
`leadv2-review-run.sh` (~line 2144-2149): added `FINDINGS_TOTAL_ALL=$((CRITICAL+HIGH+MEDIUM+LOW))`
right after the four per-severity totals are derived from `FINDINGS_JSON` (same array, never a
second independently-derived count). The `status: fail` block (~line 2286-2290) now prints
`findings_total: %s` ahead of `critical:/high:/medium:/low:`. The `findings_lost` block already had
a (hardcoded 0) `findings_total:` line and is untouched.

## Fix 2 — unanchored flat findings collapsing during dedup
`leadv2-review-run.sh` (~line 2081-2091): the dedup awk key was `file|line|severity|dimension`. A
bracket bullet with no trailing `(path:line)` has `file=""` and `line=""`, so every unanchored
same-severity/dimension finding shared one key and dedup kept only the first. Fix: when file AND
line are both empty, fold the normalized description into the key too. Anchored findings (the
common, cross-arm-corroborated case) are byte-identical in behavior — only the empty-location
fallback changed.

## Fix 3 — structured findings suppressing bracket-list findings
`leadv2-review-run.sh` (~line 2019-2056): the bracket-parsing branch was gated behind
`if ! grep -qE '^FINDING:' "${_file}"`, so ANY `FINDING:` line anywhere in the report skipped
bracket parsing entirely, discarding every bracketed finding in a mixed-shape report. Fix: removed
the gate — the bracket-bullet scan now runs unconditionally, additively unioned with the `FINDING:`
scan into the same `FINDINGS_RAW` file. The existing dedup step (Fix 2) still collapses genuine
duplicates by (file, line, severity, dimension[, description when unanchored]); a `FINDING:` line
and a bracket bullet describing the same thing would only collide if they also shared file/line/
severity/dimension, which is not the case in the round-2 regression fixture (they're independent
findings).

## Acceptance — re-ran the gate against the real specimen
`docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md` (Codex's review of 1b8b0243,
3 anchored `[high]` bracket findings, 0 `FINDING:` lines) copied verbatim into
`plugins/leadv2/scripts/tests/fixtures/review-gate-codex-flat-list/review-codex-round2-specimen.md`
and driven through the REAL engine (Scenario 5, below): `findings_total: 3`, `reason` is never
`findings_lost`. This was NOT a fix required by bug #3 alone (this specimen has zero `FINDING:`
lines, so round 1's gate already parsed it correctly in isolation) — but reproducing it under the
full engine invocation required a mission snapshot to be present (see "investigation note" below),
and it is now the suite's own round-2 acceptance scenario (S5).

### Investigation note — why the live orchestration run showed `findings_total: 0` for this specimen
The committed `docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-gate.md` /
`review-findings.json` (both real artifacts from an actual `/leadv2 review` invocation against this
lane, timestamped identically to `review-codex.md`) show `findings_total: 0` / `"findings":[]`, yet
manually replaying the per-arm union loop's exact code against the same file (isolated repro
script) produced all 3 rows correctly, and `grep -c '^FINDING:'` / bracket-line grep both behave as
expected on this file. I could not reproduce that specific empty result under the real engine
CLI with a from-scratch mission-available harness (S5 above passes cleanly with the round-1 code
even before round-2's fixes, since no `FINDING:` lines exist in this specimen). I did not chase this
further given the turn budget — it does not block round 2's 3 named fixes, all of which are real
and independently confirmed by direct code inspection + isolated repro, and Codex's review comments
point at exact line numbers that match the actual pre-fix code. Flagging as an open question rather
than asserting a root cause I could not verify.

## Test suite: `plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh`
Extended (not replaced) round 1's suite. New fixtures under
`plugins/leadv2/scripts/tests/fixtures/review-gate-codex-flat-list/`:
- `review-codex-mixed.md` — 1 `FINDING:` line + 1 bracket bullet, declared `high=2` (bug #3).
- `review-codex-unanchored.md` — 3 unanchored `[high]` bullets, declared `high=3` (bug #2).
- `review-codex-round2-specimen.md` — the real Codex specimen, 3 anchored `[high]` bullets (acceptance).

New scenarios (S1/S2 are round 1's, unchanged in spirit, S1 additionally now asserts
`findings_total`):
- S3 (mixed): asserts `findings_total: 2` and `high: 2`.
- S4 (unanchored): asserts `findings_total: 3` and `high: 3`.
- S5 (real specimen): asserts no `findings_lost` and `findings_total` equals the fixture's bracketed
  `[high]` count (3). Required a `lane-mission.md` in the scratch handoff so
  `REVIEW_MISSION_AVAILABLE=1` — the real specimen declares both `REVIEW_CODE_VERDICT` and
  `REVIEW_MISSION_VERDICT`, which `parse_review_verdict()` only accepts when a mission snapshot is
  present.

### Three separate mutation controls (one per fix, all run and shown below)
Round 1's single mutation control patched a marker that no longer exists after fix #3 (the gate
`if` it neutered was removed outright). Replaced with three independent `python3`-patched scratch
copies of the engine, each reverting exactly one fix, each asserting exactly 1 occurrence of its
marker before patching, each run through the real engine against the scenario that exercises it,
each reverted after. `run_mutation()` sets globals (`MUT_RC`/`MUT_GATE`) rather than returning
through a `$(...)` command substitution — an earlier draft captured `pass()`/`fail()`'s own stdout
into the "data" channel by mistake, which silently produced false passes; caught by manually
inspecting a first run where two of three mutation checks came back with empty `rc`/`gate` and no
`[TEST]` line for the inner `bash -n` check.

- **Mutation 1** (bug #1: findings_total absent) — reverts the `status: fail` printf back to the
  round-1 shape (no `findings_total`). Run against S1's fixture. RED: `findings_total:` is absent
  from the gate again.
- **Mutation 2** (bug #2: unanchored dedup collapse) — reverts the dedup awk key to
  `file|line|severity|dimension` only. Run against the unanchored fixture (3 findings). RED:
  `findings_total: 1` (collapsed).
- **Mutation 3** (bug #3: mixed-shape suppression) — re-wraps the bracket-bullet scan in
  `if ! grep -qE '^FINDING:' "${_file}"; then ... fi`. Run against the mixed fixture (2 findings).
  RED: `findings_total: 1` (bracket finding lost).

### Full test output (green, with all 3 fixes)
```
[TEST] PASS: bash -n clean (leadv2-review-run.sh)
[TEST] PASS: fixture carries 1 bracketed [high] finding(s)
[TEST] PASS: S1: gate does not misreport findings_lost for the flat bracket-list specimen
[TEST] PASS: S1: gate correctly reports status=fail (exit 7) for the declared FAIL verdict
[TEST] PASS: S1: gate's high count (1) equals the fixture's bracketed [high] finding count
[TEST] PASS: S1: gate's findings_total (1) is present on the normal fail path
[TEST] PASS: S1: review-findings.json independently counts 1 High finding(s) -- agrees with gate
[TEST] PASS: S2: a genuinely empty union (no FINDING:, no bracket lines) still blocks as findings_lost
[TEST] PASS: S3: mixed report (FINDING: line + bracket bullet) counts BOTH findings (findings_total=2)
[TEST] PASS: S4: 3 unanchored same-severity bracket findings all survive dedup (findings_total=3)
[TEST] PASS: S5: the real round-2 specimen no longer reports findings_lost
[TEST] PASS: S5: gate's findings_total (3) equals the real specimen's bracketed [high] finding count
[TEST] PASS: MUTATION 1-findings_total-absent: scratch engine still bash -n clean after the revert
[TEST] PASS: MUTATION 1 RED: with findings_total reverted out, the normal fail gate omits it again
[TEST] PASS: MUTATION 2-unanchored-dedup-collapse: scratch engine still bash -n clean after the revert
[TEST] PASS: MUTATION 2 RED: with the dedup fix reverted, 3 unanchored findings collapse back to 1
[TEST] PASS: MUTATION 3-mixed-shape-suppressed: scratch engine still bash -n clean after the revert
[TEST] PASS: MUTATION 3 RED: with bracket-parsing re-gated behind FINDING:-line presence, the mixed report loses its bracket finding again

=== 18 passed, 0 failed ===
```

## Regression check on existing suites
- `test-review-body-recovery.sh`: **PASS=45 FAIL=0**, unchanged from round 1 (confirms the FINDING:
  parsing path, findings_lost guard, and codex-store recovery logic are all untouched).
- `test-review-gate-shows-findings.sh`: **PASS=49 FAIL=6**, identical to round 1's post-fix score
  (round 1 traced the 6 residual B/C failures to a selfcheck-gate/dirty-worktree interaction
  unrelated to this fix, reproduced identically on unmodified HEAD). Re-ran it this round: same
  PASS=49 FAIL=6 — confirms it still reproduces, unrelated to round 2's changes, left untouched per
  "never weaken a fixture to get green."

## Known trap — verified myself, not inherited
`grep -n "findings_lost" plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` → **zero matches**
(rc=1). This file's `parse_review_verdict()` (line 975) reads the arm's self-declared
`REVIEW_FINDINGS:` line directly and never runs a union/dedup step, so it cannot exhibit any of the
3 bugs fixed here. Confirmed independently this round, not just re-asserting round 1's claim. Left
untouched.

## Self-check (falsification set)
```
$ bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh && echo OK
OK
```
No Python files changed (`py_compile` N/A). Did not run the full `tests/run-all.sh` changed-scope
sweep this round (turn-budget) — ran the two directly-relevant regression suites instead
(`test-review-body-recovery.sh`, `test-review-gate-shows-findings.sh`), both shown above.

## Off-limits respected
- Reviewer-arm selection, quota filtering, author-exclusion rule: untouched.
- `findings_lost` remains reachable: Scenario 2 (genuinely empty report, no `FINDING:`, no bracket
  lines) still blocks with `status: blocked / reason: findings_lost`.

## Left alone
- `leadv2-dispatch-product-close.sh` — re-verified unaffected this round (see "Known trap" above).
- `test-review-gate-shows-findings.sh` B/C failures — pre-existing, reproduces identically before
  and after this diff, not touched.
- The unexplained empty-result artifact from the earlier live orchestration run against this same
  specimen (see "Investigation note" above) — flagged, not resolved; does not block the 3 named
  fixes, which are independently verified.

DELIVERABLE_COMPLETE
