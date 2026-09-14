# PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01

## Problem

`leadv2-review-run.sh` reported `status: blocked / reason: findings_lost /
findings_total: 0` for a real Codex adversarial review
(`~/Projects/persona-engine/docs/handoff/V5-M1-CI-SELECTION-R2/review-codex.md`)
that declared `REVIEW_VERDICT: FAIL` / `REVIEW_FINDINGS: critical=0 high=1
medium=0 low=0` and wrote its one finding as a flat bracket-severity bullet:

```
- [high] Unsupported CI timeout decision (docs/handoff/V5-M1-CI-SELECTION-R2/build-attempt-1.diff:102-111)
```

## Two emit sites — both found and diagnosed

`grep -rn "review_gate" plugins/leadv2/` finds `review_gate` decision lines in
two writers:

1. **`plugins/leadv2/scripts/leadv2-review-run.sh`** (the standalone `/leadv2
   review` engine, invoked directly per `plugins/leadv2/docs/phases.md`,
   `plugins/leadv2/skills/leadv2-review/*`). **This is where the bug lives and
   where the fix landed.** Its per-arm union loop (around line 2007, feeding
   `FINDINGS_RAW` → `FINDINGS_DEDUP` → `review-findings.json` →
   `FINDINGS_CRITICAL_TOTAL`/`FINDINGS_HIGH_TOTAL`) recognized only
   `^FINDING: severity=... file=... line=... desc=...` lines. A flat
   bracket-severity report produced zero rows, so the "declared FAIL but zero
   Critical/High" impossible-state check (line ~2111) fired and printed
   `status: blocked\nreason: findings_lost\nfindings_total: 0` over a review
   that was never lost.

2. **`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`** (the
   product-close lane's inline gate — the live path per the KNOWN TRAP).
   **Verdict: NOT broken by this bug, no fix needed.** Its `parse_review_verdict()`
   (line 975) never re-derives counts from the report body at all — it reads
   the arm's own self-declared `REVIEW_FINDINGS: critical=X high=Y medium=Z
   low=W` line directly (`sed -nE '...REVIEW_FINDINGS:...'`, line 999) and
   uses those numbers verbatim as `FINDINGS_CRITICAL`/`FINDINGS_HIGH`. It has
   no independent per-finding union and no "findings_lost" reason string
   anywhere in the file (confirmed: `grep -n findings_lost
   leadv2-dispatch-product-close.sh` → no matches). For the specimen's
   `REVIEW_FINDINGS: critical=0 high=1 medium=0 low=0` line, this path already
   yields `FINDINGS_HIGH=1` and renders a normal `status: fail` — it was never
   exposed to the failure mode described in the task. `grep -rn
   "reason=findings_lost\|findings_total"` across the whole plugin tree
   confirms the literal `findings_lost`/`findings_total: 0` strings exist
   ONLY in `leadv2-review-run.sh`.

   Separately, both writers already share the same DISPLAY renderer,
   `leadv2-review-findings.sh` (`render_gate_findings`), which turns out to
   already understand this exact bracket shape as `bracket_lines` (its own
   header names the incident: `CODEX-REVIEWS-LOSE-THEIR-FINDINGS-TEXT-01`,
   `dispatch-199f5d8e`) — but that renderer only produces the *display* block
   appended to `review-gate.md` after the verdict is decided. It is never
   consulted by `leadv2-review-run.sh`'s own independent count-and-block
   logic, which is exactly the gap this task closes.

## Fix

`plugins/leadv2/scripts/leadv2-review-run.sh`, per-arm loop (~line 2007):
additive branch — only runs when the arm's report has zero `^FINDING:` lines
— that parses `^[[:space:]]*-[[:space:]]*\[(Critical|High|Medium|Low)\]`
bullets, extracting severity, trailing `(path:line)` anchor when present, and
description, into the same TSV row shape the existing `FINDING:` branch
writes. No existing shape was touched or replaced.

`findings_lost` remains reachable: a report with neither `FINDING:` lines nor
bracket lines (Scenario 2 in the new test) still blocks with
`status: blocked / reason: findings_lost`.

## Test

New: `plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh`
(self-registered via `# run-all-triggers: leadv2-review-run.sh
leadv2-review-findings.sh` header, admitted once git-tracked per
`leadv2-suite-discovery.sh`'s tracked-admission contract).

Fixture: `plugins/leadv2/scripts/tests/fixtures/review-gate-codex-flat-list/review-codex.md`
— the real specimen copied verbatim from persona-engine.

Drives the REAL `leadv2-review-run.sh` end to end (same harness pattern as
`test-review-body-recovery.sh`: `LEADV2_GLM_POLICY_RESOLVER` +
`LEADV2_DISPATCH_ARCHITECT_BIN` stubs, no reimplementation of the parser).

- Scenario 1 (positive): feeds the fixture verbatim as the reviewer body.
  Asserts the gate does NOT report `findings_lost`, reports `status: fail`
  (exit 7), and `high: 1` — equal to `grep -c '\[high\]' <fixture>` (the
  acceptance probe's own count) — and that `review-findings.json`
  independently counts 1 High finding via a separate `python3 json.load`
  (never the production script's own grep, to avoid a shared-bug tautology).
- Scenario 2 (negative control, real case): a declared `FAIL high=5` with
  NEITHER `FINDING:` nor bracket lines still blocks as `findings_lost` —
  proves the guard the task says must "remain reachable" still is.
- Mutation control (required negative control, run and shown below): a
  scratch copy of the engine has the new branch's guard replaced with
  `if false; then` via a `python3` patch that asserts exactly 1 occurrence,
  re-run against the SAME fixture through the SAME harness, reverted after.

### Full test output (green, with fix)

```
[TEST] PASS: bash -n clean (leadv2-review-run.sh)
[TEST] PASS: fixture carries 1 bracketed [high] finding(s)
[TEST] PASS: S1: gate does not misreport findings_lost for the flat bracket-list specimen
[TEST] PASS: S1: gate correctly reports status=fail (exit 7) for the declared FAIL verdict
[TEST] PASS: S1: gate's high count (1) equals the fixture's bracketed [high] finding count
[TEST] PASS: S1: review-findings.json independently counts 1 High finding(s) -- agrees with gate
[TEST] PASS: S2: a genuinely empty union (no FINDING:, no bracket lines) still blocks as findings_lost
[TEST] PASS: MUTATION: scratch engine still bash -n clean after neutering the bracket-list branch
[TEST] PASS: MUTATION RED: with the bracket-list branch neutered, the real specimen (mis)reports findings_lost again

=== 9 passed, 0 failed ===
```

### Negative control detail (mutation RED, captured inside the suite)

The suite's own "MUTATION RED" line above IS the required negative control:
it copies the engine to scratch, replaces the new guard
(`if ! grep -qE '^FINDING:' "${_file}" 2>/dev/null; then`) with `if false;
then` (asserting exactly one occurrence first), confirms `bash -n` still
clean, re-runs the SAME fixture through the SAME harness against the mutated
engine, and asserts it goes back to `status: blocked / reason: findings_lost`
— i.e. RED without the fix, exactly reproducing the original defect — then
deletes the scratch copy (the real engine file was never touched).

## Regression check on existing suites

- `test-review-body-recovery.sh` (the pre-existing suite covering this exact
  engine's FAIL/findings/findings_lost logic, 8 scenarios + 2 mutation
  controls): **PASS=45 FAIL=0**, unchanged behavior for every existing shape
  (`FINDING:` lines, codex-store recovery, declared-but-unfindable
  `findings_lost`, its own MUTATION-C/D controls).
- `test-review-gate-shows-findings.sh`: pre-existing baseline on unmodified
  HEAD is **PASS=39 FAIL=16** (Parts B and C fail today, before this task's
  change, due to an unrelated `leadv2-dispatch-product-close.sh` selfcheck
  gate — `reason=selfcheck_failed` / `writes_csv_empty` — reacting to the live
  worktree's dirty git diff during the suite's own `run_close`/engine
  invocations; verified by reverting `leadv2-review-run.sh` to
  `git show HEAD:...` and re-running: identical B1/B2/C1 failures). With this
  task's fix applied the same suite scores **PASS=49 FAIL=6** — strictly
  better, not worse. Part A (the renderer's own 39 checks, including the
  `bracket_lines` A9 case) is 100% green in both runs. None of the residual
  failures are new or caused by this diff.

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK
$ /bin/bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh && echo OK
OK
$ /bin/bash -n plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh && echo OK
OK
```

No Python files were changed (`py_compile` N/A).

## Off-limits respected

- Reviewer-arm selection, quota filtering, author-exclusion rule: untouched.
- The gate was NOT relaxed: `findings_lost` still fires for a genuinely
  unreadable/empty report (Scenario 2, above).

## Left alone

- `leadv2-dispatch-product-close.sh` — investigated, confirmed unaffected by
  this defect (see "Two emit sites" above), left untouched.
- The pre-existing `test-review-gate-shows-findings.sh` B/C failures — traced
  to a selfcheck-gate/dirty-worktree interaction unrelated to this fix (proven
  identical on unmodified HEAD); not touched, since "never weaken a fixture to
  get green" and this is an environment-sensitive finding, not a regression
  from this diff.

## Round 2

Codex's own review of round 1 (`1b8b0243`) — `docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md`
— found 3 `[high]` defects in the round-1 fix itself. All 3 fixed in `leadv2-review-run.sh`:

1. **`findings_total` absent on the normal `status: fail` path.** Added
   `FINDINGS_TOTAL_ALL=$((CRITICAL+HIGH+MEDIUM+LOW))` (same array the per-severity counts already
   come from) and print it ahead of `critical:/high:/medium:/low:` in the fail block.
2. **Unanchored bracket findings collapsed during dedup.** The dedup key was
   `file|line|severity|dimension`; an unanchored bullet has empty file/line, so every same-severity
   unanchored finding shared one key. Fixed: fold the normalized description into the key when file
   AND line are both empty. Anchored findings (the common case) are unaffected.
3. **Structured findings suppressed bracket-list findings.** The bracket-bullet scan was gated
   behind "report has zero `FINDING:` lines" — any `FINDING:` line anywhere lost every bracketed
   finding. Fixed: bracket scan now runs unconditionally, additive to the `FINDING:` scan, same
   `FINDINGS_RAW` union, dedup (fix #2) still collapses genuine duplicates.

**Acceptance:** the real specimen (`review-codex.md`, 3 anchored `[high]` findings, copied into
`plugins/leadv2/scripts/tests/fixtures/review-gate-codex-flat-list/review-codex-round2-specimen.md`)
now reports `findings_total: 3` through the real engine, never `findings_lost` (test suite
Scenario 5).

**Tests:** `test-review-gate-codex-flat-list.sh` extended with S3 (mixed shape), S4 (unanchored
multi), S5 (real specimen), and an `findings_total` assertion added to S1. Three SEPARATE mutation
controls, one per fix (each patches a scratch engine copy, asserts exactly 1 marker occurrence,
runs the scenario that exercises that fix, shows RED, reverts) — round 1's single mutation control
no longer applied since fix #3 removed the marker it patched. All 18 checks green; all 3 mutations
RED without their fix. Full output in `docs/handoff/dispatch-e6816fbf/developer.full.md`.

**Regression:** `test-review-body-recovery.sh` PASS=45 FAIL=0 (unchanged). `test-review-gate-shows-findings.sh`
PASS=49 FAIL=6, identical to round 1's post-fix score (pre-existing, unrelated selfcheck-gate
interaction, reproduces on unmodified HEAD).

**Known trap, re-verified (not inherited):** `grep -n findings_lost plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`
→ zero matches. That file's `parse_review_verdict()` reads the arm's self-declared `REVIEW_FINDINGS:`
line directly with no union/dedup step, so it cannot exhibit any of these 3 bugs. Confirmed
independently this round. Left untouched.

**Open item, not resolved:** the committed `review-gate.md`/`review-findings.json` artifacts from
an earlier live `/leadv2 review` run against this lane show `findings_total: 0` for the same
specimen that reproduces correctly (`findings_total: 3`) under my isolated repro and under the test
suite's real-engine harness. Could not reproduce the empty result under the real CLI within the
turn budget; flagged in `developer.full.md` rather than asserting an unconfirmed root cause. Does
not block the 3 named fixes, which are independently verified by direct code inspection.

DELIVERABLE_COMPLETE
