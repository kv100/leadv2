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

## Round 3

**Verdict: no source change made.** All three findings Codex re-reported (H1/H2/H3, in
`docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md`) describe the round-1 code,
not round-2's committed fix. Root cause of round 2's own "open item" (why the live gate artifact
showed `findings_total: 0` while isolated repro showed 3) is now explained, not just flagged:

```
$ git log --format='%H %ci %s' -3 -- plugins/leadv2/scripts/leadv2-review-run.sh
5e9274e7... 2026-09-14 23:04:19 +0300 fix(review-gate): round 2 -- findings_total, unanchored dedup, mixed-shape parsing
1b8b0243... 2026-09-14 22:21:52 +0300 fix(review-gate): recognize flat bracket-severity findings (Codex shape)
4410095a... 2026-09-14 17:30:35 +0300 fix(review): bind verdict to mission snapshot

$ stat -f '%Sm' docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-codex.md docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-gate.md
Sep 14 22:43:46 2026
Sep 14 22:43:46 2026
```

`review-codex.md` was generated at 22:43:46 — **after** round 1 (1b8b0243, 22:21:52) but **before**
round 2 (5e9274e7, 23:04:19). Codex reviewed round-1's code (bracket parsing gated behind zero
`FINDING:` lines, unfolded dedup key, no `findings_total` on the fail path) and correctly found
all three bugs at those exact line numbers. Round 2 fixed all three ~20 minutes later. The round-3
mission text's framing ("Round 2 landed 5e9274e7. Codex reviewed it...") does not match the file
timestamps — Codex reviewed round 1, and the stale artifact was never regenerated against round 2.

### H1 (structured findings suppress bracket findings) — already fixed
`leadv2-review-run.sh:2007-2057`: the `FINDING:` scan (2010-2018) and the bracket-bullet scan
(2019-2056) both run **unconditionally**, additively unioned into the same `FINDINGS_RAW`, for
every arm in `ran_arms`. No `if`/gate around the bracket branch exists in the current tree.
Covered by test Scenario 3 (mixed shape) and Mutation Control 3 below.

### H2 (unanchored findings collapse in dedup) — already fixed
`leadv2-review-run.sh:2100-2106`: `awk -F'\t' '{key=$3"|"$4"|"$2"|"$5; if ($3 == "" && $4 == "") { key = key "|" $6 }; ...}'`
folds the normalized description (`$6`) into the dedup key whenever both file and line are empty.
Covered by test Scenario 4 (3 unanchored same-severity bullets) and Mutation Control 2 below.

### H3 (`findings_total` absent on the normal gate path) — already fixed
The fail-path printf (`leadv2-review-run.sh`, `status: fail` block) emits `findings_total: %s`
ahead of the per-severity fields, sourced from `FINDINGS_TOTAL_ALL` (a count over the deduped
union, independent of any per-severity sum). Covered by test Scenario 1 and Mutation Control 1
below.

### Tests — full suite, this round, unmodified engine
```
$ bash plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh
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

### Negative controls (from the existing suite, one per finding, all three RUN this round)
- **Mutation 1** (H3 — findings_total absent): reverts the `status: fail` printf to the round-1
  shape (per-severity fields only). RED: `findings_total:` absent from the gate again. GREEN on
  the unmodified engine: `findings_total: 1` present (S1).
- **Mutation 2** (H2 — unanchored dedup collapse): reverts the dedup awk key to drop the
  description fallback. RED: 3 unanchored `[high]` bullets collapse to `findings_total: 1`. GREEN
  on the unmodified engine: `findings_total: 3` (S4).
- **Mutation 3** (H1 — mixed-shape suppression): re-gates the bracket scan behind
  `! grep -qE '^FINDING:'`. RED: the mixed-shape fixture (1 `FINDING:` line + 1 bracket bullet)
  drops back to `findings_total: 1`. GREEN on the unmodified engine: `findings_total: 2` (S3).
All three pairs are in the raw suite output above (Mutation N + its preceding scenario).

### The acceptance that matters — before/after on the real specimen
**Before** (committed artifact, generated 22:43:46 against round-1 code, predates round 2's fix):
```
status: blocked
reason: findings_lost
arms: codex
declared_verdict: FAIL
findings_total: 0
```
**After** (fresh isolated run of the SAME `review-codex.md` file through the current, unmodified
`leadv2-review-run.sh`, real engine CLI, stubbed reviewer-arm output = the fixture verbatim):
```
correctness_verdict: FAIL
mission_verdict: FAIL
status: fail
findings_total: 3
critical: 0
high: 3
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] .../review-mission-source.md:20 — Required findings_total is absent (...)
- [High] plugins/leadv2/scripts/leadv2-review-run.sh:2040 — Unanchored flat findings collapse during deduplication (...)
- [High] plugins/leadv2/scripts/leadv2-review-run.sh:2028 — Structured findings suppress all bracket-list findings (...)
```
`findings_total: 3`, `status: fail` — matches Codex's declared verdict exactly, never
`blocked`/`findings_lost`. This is also exactly what the suite's own Scenario 5 already asserts
against the identical fixture (`fixtures/review-gate-codex-flat-list/review-codex-round2-specimen.md`,
byte-identical to `review-codex.md`, `diff -q` confirmed).

### Self-check
```
$ bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-review-gate-codex-flat-list.sh && echo OK
OK
```
No files changed this round (no diff to review), so no Python compile step and no changed-scope
test-runner invocation applies.

### Off-limits respected
- Reviewer-arm selection, route arbiter, quota logic: untouched (verified — no edits made anywhere
  this round).
- `findings_lost` remains reachable: Scenario 2 (genuinely empty report) still blocks with that
  reason.
- No gate made more permissive — the gate was not touched at all.

### Left alone
- The stale `docs/handoff/PLUGIN-REVIEW-GATE-CODEX-FLAT-LIST-01/review-gate.md` /
  `review-codex.md` artifacts — left as-is; they are the "before" evidence for this exact round,
  and are pre-existing untracked files, not lane state this task owns.
- `leadv2-dispatch-product-close.sh`'s separate `review_gate` emission site — out of scope for
  this row (parser + gate artifact in `leadv2-review-run.sh` only, per this round's Off-limits).

DELIVERABLE_COMPLETE
