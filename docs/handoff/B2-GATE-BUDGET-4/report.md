# B2-GATE-BUDGET-4 — the close gate reaches a verdict inside its budget

Lane: `worktree-B2-GATE-BUDGET-4`, base `main@9a04ee3f` (merge-base, stateless
B6 semantics). Commits: `f3a94f16` (anchor) → `dfd37717` (run-all ceiling +
known-red budget skip + budget suite) → `a33a78fc` (wrapper ceiling in budget
scopes only + case 9) → `ee6f6b8d` (wrapper skip seam + M3 suite) →
`ee84f851` (gone-green full-set detection made positional — see "Defect found
by the first gate run" below). Not merged; not pushed; lead verifies and
merges.

## The verdict (direction 3 + 1 combined)

`leadv2-phase8-e2e-gate.sh B2-GATE-BUDGET-4` on this machine, this lane —
TWO runs, both terminal, both inside budget, neither rc=124:

Run 1, at `ee6f6b8d` (2026-09-09, started by the prior session 00:46,
completed 00:58, read from its log — the session died mid-run, the gate did
not):

```
run-all: 15 passed, 1 failed, 0 known-red (allow-listed, non-blocking), 0 known-red-skipped (budget mode, still run by --scope all), 14 gone-green (remove from allow-list), scope=changed
e2e_gate task=B2-GATE-BUDGET-4 verdict=fail elapsed_s=690 budget_s=900
```

Run 2, at `ee84f851` (the gone-green fix; this session):

```
run-all: 15 passed, 1 failed, scope=changed
e2e_gate task=B2-GATE-BUDGET-4 verdict=fail elapsed_s=456 budget_s=900
```

The acceptance criterion — *a verdict, any verdict, inside the budget,
terminal value not a log string* — is met twice: `verdict=fail` with rc=1,
elapsed 690s and 456s against 900s. Run 2 is also 234s faster than run 1
(machine load fell between runs; both still under half-to-three-quarters
budget).

**Why verdict=fail, and why that is not this lane's diff.** The single
blocking entry in both runs is the core-offline wrapper, failing the same
THREE nested suites: `shared-sink test guard`, `dod gate suite registration`,
`test-suite-lock-scope.sh`. Attribution, with artifacts:

1. All three are **green in isolation on this lane**, same commit, same
   morning (rc=0; 35/0, 16/0, 12/0 — output in
   `mutation-control`-adjacent run logs quoted in the falsification set).
2. During both gate runs, **2–4 foreign lanes were running the same
   machinery**: pids + lsof cwd captured for `C4-OVERRIDE-TRIAGE`,
   `A3-LAUNCH-REGISTRY-2`, `A1-CODEX-TIERS-B` (leadv2 worktrees) and
   `ANTISILENCE-OUTSIDE` (persona-engine), all executing
   `tests/run-all.sh --scope changed`.
3. The failure shape is concurrency, not logic: the shared-sink failures are
   `real journal not found at .../suite.L3JRQA/home/.claude/cache/... (cannot
   byte-guard)` — per-suite scratch fixtures VANISHING mid-suite. That suite
   family itself runs `leadv2-journal-fixture-purge.sh`; concurrent runners
   purge each other's just-created fixture files (known pattern:
   core-offline-reds-under-concurrent-runners).
4. A direct wrapper run on this lane while the foreign lanes were live
   reproduced the identical 3 failures (WRAP_RC=1,
   `suites passed=10 failed=3`).

Proposed row (not this lane's write set): *core-offline suite hermeticity
under concurrent runners — per-suite scratch HOMEs must be immune to a
foreign lane's fixture purge; today 2+ concurrent run-all runners flip
shared-sink/dod-gate/suite-lock-scope NOT-KNOWN-RED deterministically.*

## Defect found by the first gate run (fixed in `ee84f851`)

Run 1's summary carried **`14 gone-green (remove from allow-list)`** — from a
run that executed 13 of 95 suites. The gone-green seam I shipped in
`dfd37717` decided "full-set run" by grepping the wrapper transcript for ANY
`verdict=full_set_fallback` SCOPE_RESULT plus ANY `suites passed=` line. But
nested suites inside the wrapper print their OWN SCOPE_RESULT/summary lines
mid-transcript (a nested test simulated a full-set fallback), so a narrowed
run minted 14 false `[KNOWN-RED-GONE-GREEN]` lines — each prescribing an
allow-list removal the run never earned. Unsafe direction: the allow-list
would shrink on evidence that does not exist.

Fix: full-set is now decided from the wrapper's OWN lines, positionally — its
own SCOPE_RESULT is the FIRST in the transcript (printed before any suite can
run), and its own summary must follow the LAST SCOPE_RESULT line (a FATAL or
truncated transcript never reaches it). Case 10 of the budget suite pins the
exact gate-log shape and is RED on the pre-fix run-all.sh (proven via
`LEADV2_TEST_RUN_ALL=<git show HEAD~1:tests/run-all.sh>`: `FAIL: (10) false
gone-green from nested transcript` — and the false signal is visible in the
old output: `1 gone-green (remove from allow-list)` from a narrowed run).
Case 11 pins the counter-direction: the wrapper's OWN failed-open fallback
STILL mints gone-green. Run 2's summary above shows the fix live: no
gone-green count, no false removals.

## What was built

**Direction 3 — per-suite ceiling (`tests/run-all.sh`).** Every suite runs
under `_run_all_timeout_run` with a per-suite ceiling (`LEADV2_RUN_ALL_SUITE_TIMEOUT_S`,
default 600s). A suite that exceeds it is killed and reported as a NAMED
blocking failure before classification:

```
[SUITE-TIMEOUT] tests/test-hang.sh exceeded 3s ceiling (killed by run-all; counted as a blocking failure with a named cause)
```

The wrapper (`run-core-offline.sh`, always-on entry 1) is ceilinged ONLY in
budget scopes (`--scope changed`/`changed-since`); `--scope all` — the nightly
full sweep in CI (120-min budget) — is deliberately exempt so the one place
allow-listed suites still execute cannot be killed by a close-gate-sized
ceiling. A ceiling-killed wrapper stays blocking even when its partial
transcript shows only allow-listed failures (no laundering a kill into
known-red): classification is skipped for rc=124.

**Direction 1 — known-red out of the CLOSE budget, not out of runs.**
`tests/run-all.sh` forwards `LEADV2_CORE_OFFLINE_SKIP_KNOWN_RED=1` + the
allow-list path to the wrapper in its budget scopes only. The wrapper
(`plugins/leadv2/scripts/tests/run-core-offline.sh`) then skips allow-listed
labels — one loud line each, counted in its summary:

```
[CORE-OFFLINE] KNOWN-RED-SKIP: lane truth batch (log_path + quarantine convergence)
[CORE-OFFLINE] known-red skipped=1 (budget mode: still executed by --scope all / bare runs)
[CORE-OFFLINE] suites passed=4 failed=0 missing=0 known_red_skipped=1 repo=...
```

run-all relays these as `[KNOWN-RED-SKIP] core:<label> — skipped in budget
mode (scope=changed); still executed by --scope all (nightly full sweep)` and
counts them in its summary. The skip is scope-gated inside the wrapper's own
`_core_offline_skip_requested()`: a bare invocation or `--scope all` NEVER
skips, even if the env leaks in — the wrapper enforces the
"still executed somewhere" half itself. Where known-red suites still execute:

1. **CI nightly full sweep** — `.github/workflows/test-suites.yml` runs
   `ci-gate.sh all` at 06:00 UTC with a 120-min budget, `--scope all`, no skip.
2. **Any bare `run-core-offline.sh` invocation** (no scope) — full curated
   set, no skip.
3. **PR CI** (`ci-gate.sh changed`) gets the budget-mode skip and relays the
   same `[KNOWN-RED-SKIP]` lines.

Where red→green transitions surface: a label that PASSES a full-set run
produces `[KNOWN-RED-GONE-GREEN] core:<label> — passed a full-set run; remove
the entry from tests/known-red-suites.txt (the list may only shrink)` — fired
only when the wrapper actually ran the full set (`--scope all` asked by
run-all, or the wrapper's own `verdict=full_set_fallback`), never from a
narrowed run. `tests/known-red-guard.sh` (nightly) additionally refuses any
allow-list growth. The allow-list entry count is unchanged by this lane
(header comment only) — the list may only shrink.

**Wrapper ladder fix (enabler, same commit `ee6f6b8d`).** The wrapper's
changed-file ladder had no case for `tests/known-red-suites.txt`, so ANY lane
editing the allow-list paid a 95-suite `full_set_fallback` inside the 900s
gate (measured on this lane pre-fix: "3 changed files, 1 unmapped →
full-set fallback"). With the case + suites self-declaring
`known-red-suites(.txt)` triggers, this lane's wrapper run narrows to **13 of
95, verdict=selected, 0 unmapped**:

```
[CORE-OFFLINE] scope=changed running 13 of 95 suites (base=main@9a04ee3faa, 5 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=13 total=95 base=main@9a04ee3faa changed=5 unmapped=0 verdict=selected reason=-
```

A skip that empties the whole selection is itself a named verdict, not a
silent empty pass: `verdict=nothing_to_run reason=known_red_skip_emptied_selection`.

## Measurements (direction 2 — inside the green bash32 suite)

All timings on this machine (darwin), each taken more than once; the reported
number is stated per row. Baseline vs lead's brief in the last column.

| What | Measured here | Runs | Lead's brief |
|---|---|---|---|
| `tests/test-status-surface-bash32.sh`, whole suite, green | **281s** | 2 (281s both) | ~321s |
| `test-lane-truth-batch-01.sh` inside the REAL wrapper, red, allow-listed | **151s** | 1 valid (env-isolated attempt was invalid — broke the fixture; redone via `LEADV2_SUITE_DEFS_OVERRIDE` inside the real wrapper) | ~355s |
| One synchronous status-surface wrapper call (`LEADV2_STATUS_SYNC=1`, env -i, minimal PATH) | **56s / 45s** | 2 pairs | — |
| Renderer alone (`--all`, same env) | **18s / 22s** | same 2 pairs | — |
| Label resolution inside the renderer | **18ms** | 1 | — |

**Where bash32's ~281s goes:** the suite performs ~7 synchronous
(`LEADV2_STATUS_SYNC=1`) wrapper invocations. One such call costs 45–56s
paired, while the renderer it wraps costs 18–22s alone — the wrapper is
~2.5× its renderer. The renderer's own 18–22s is enumeration-bound (it walks
~1206 lanes across 15 projects, ~9289 output lines); label resolution is NOT
the cost (18ms). So ≈7 × ~40s ≈ 281s, consistent with the whole-suite
measurement.

**New rows proposed (not implemented — direction 2 is measure-only here):**
1. *Per-call sync wrapper cost*: one `LEADV2_STATUS_SYNC=1` wrapper call
   costs 45–56s where its renderer costs 18–22s — find the 2.5× (subshell
   re-enumeration, per-project state reloads) and one wrapper call drops
   toward renderer cost; bash32 would fall from ~281s to well under 150s.
2. *Seven synchronous calls*: whether bash32 needs sync semantics for all 7
   invocations or some can tolerate the async/cached path.

**Contradiction with the brief, stated plainly:** lane-truth-batch-01 =
151s here, not 355s; bash32 = 281s, not 321s. Same magnitude, different
constants — machine load during the lead's measurement is the likely cause.
Direction unchanged (these two suites dominate the budget); the constants in
the brief were not inherited silently.

## E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01 — subsumed

**SUBSUMED for the leadv2 gate path, by the existing run-all classification**
(round 3, 2026-09-02): `is_known_red()` classifies nested
`[CORE-OFFLINE] FAILED: <label>` lines against `tests/known-red-suites.txt`
(`core:` entries) → `[KNOWN-RED]` non-blocking, exit 0; only NOT-known-red
failures reach the `Failures (blocking):` block. `leadv2-e2e-ownership.sh`
parses ONLY that block, so allow-listed failures never reach the ownership
check. The proving suite `tests/test-known-red-allowlist-nested-match.sh`
exists, stayed green through this lane's edits (12/0, re-run 2026-09-09), and
case 3 of the new budget suite re-pins the classification itself.

## Negative controls (E2E-KILLRATE-01) — artifacts, not prose

All three via `plugins/leadv2/scripts/leadv2-mutation-control.sh`, applied to
marker lines INSIDE function bodies, bound to the FINAL code commit
`ee84f851` (`lane_diff_hash=13a781ab06867bf65792fec8ab80a0a2243f878314c78bf20eacf88a083215ec`;
re-run after the last non-artifact commit, so the earlier artifacts bound to
`ee6f6b8d` were superseded and removed):

| Control | Mutation | Suite goes red on | Artifact |
|---|---|---|---|
| M1 ceiling-mut-1 | `_suite_ceiling_s()` returns `0` (ceiling disabled) | `FAIL: (1) ceiling verdict failed; rc=0` — over-budget suite never killed, no `[SUITE-TIMEOUT]`, run-all exits 0 (the gate pays the full hang and still ends rc=124) | `mutation-control/20260908T220935Z-58903.txt` |
| M2 known-red-mut-1 | `is_known_red` returns 0 for everything ("exclude everything red") | `FAIL: (2) guard failed; rc=0` — a NOT-allow-listed failing nested suite no longer blocks | `mutation-control/20260908T221024Z-4411.txt` |
| M3 skip-mut-1 | budget-scope gate dropped from `_core_offline_skip_requested` (skip whenever the env is present, even bare/`--scope all`) | `FAIL: (2) bare invocation skipped allow-listed suites; rc=0` — allow-listed suites silently dropped from the one place they still execute | `mutation-control/20260908T221041Z-25827.txt` |

Each artifact records `baseline_rc=0` / `mutated_rc=1`. Both mandated
controls are present: (1) the symptom — an over-budget selection produces a
verdict, asserted on terminal VALUE (rc=1 + `[SUITE-TIMEOUT]` line + blocking
entry), not a log string; (2) the guard — a genuinely failing suite NOT on
the allow-list still fails the run, plus this lane deliberately breaks its
own exclusion rule (M2 mutates toward "exclude everything red" and the suite
catches it; M3 mutates toward "skip everywhere" and the suite catches it).

## Selection proof + measured range

- Range: `merge-base main HEAD` = **9a04ee3f** (stateless `--scope changed`).
- run-all self-registration (`LEADV2_RUN_ALL_LIST_TRIGGERS=1`): the budget
  suite registers 4 stems — `run-all`, `run-all.sh`, `known-red-suites`,
  `known-red-suites.txt` → `plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh`;
  the wrapper-skip suite registers `run-core-offline`, `known-red-suites`,
  `known-red-suites.txt` → `plugins/leadv2/scripts/tests/test-core-offline-known-red-skip.sh`.
- Wrapper narrowing for this lane's diff: 13 of 95, verdict=selected,
  0 unmapped (SCOPE_DUMP output above).

## Falsification set (all green, 2026-09-09, worktree `ee84f851`, this session)

- `bash -n` on every changed shell file (run-all.sh, run-core-offline.sh,
  both new suites) — clean, and asserted inside both suites.
- New wrapper-skip suite `test-core-offline-known-red-skip.sh`: **6/0**.
- Budget suite `test-gate-reaches-a-verdict-inside-budget.sh`: **13/0**
  (incl. case 1 = the symptom, case 2 = the guard, case 9 = nightly
  long-run property, case 10 = no false gone-green from a nested
  full_set_fallback transcript — RED on the pre-fix run-all.sh, case 11 =
  the wrapper's own fallback still mints gone-green).
- Pinning suites re-run after the gone-green fix:
  `test-known-red-allowlist-nested-match.sh` **12/0**,
  `test-run-all-forwards-scope.sh` **2/0**,
  `test-run-all-carrier-map.sh` **5/0**,
  `test-run-all-self-registration.sh` **12/0**.
- The repo's changed-scope runner = the close gate itself, run 2 above:
  `15 passed, 1 failed` → `verdict=fail elapsed_s=456 budget_s=900`, rc=1
  (the 1 failure attributed to concurrent foreign runners, evidence above).
- The three concurrency-failing nested suites, in isolation on this lane:
  `test-shared-sink-test-guard.sh` **35/0**, `test-dod-gate-suite-registration.sh`
  **16/0**, `test-suite-lock-scope.sh` **12/0** (all rc=0, while the foreign
  lanes were live — isolating hermeticity from this lane's diff).

## Files changed (`main...HEAD`, 5 commits)

- `tests/run-all.sh` — per-suite ceiling + `[SUITE-TIMEOUT]` verdict; budget-scope
  skip env forwarding; `[KNOWN-RED-SKIP]` relay; `[KNOWN-RED-GONE-GREEN]`
  (positional own-verdict full-set detection as of `ee84f851`); summary
  counters.
- `tests/known-red-suites.txt` — header comment only (entry count unchanged).
- `plugins/leadv2/scripts/tests/run-core-offline.sh` — budget-scope skip +
  `[CORE-OFFLINE] KNOWN-RED-SKIP` lines + scope-gated request + ladder case
  for `tests/known-red-suites.txt` + `known_red_skipped=N` in summary.
- `plugins/leadv2/tests/test-gate-reaches-a-verdict-inside-budget.sh` — NEW (13 cases).
- `plugins/leadv2/scripts/tests/test-core-offline-known-red-skip.sh` — NEW (6 cases).
- `docs/handoff/B2-GATE-BUDGET-4/` — this report + 3 mutation-control
  artifacts (force-added past the `docs/handoff/*/*` ignore).

## Honest limitations

- lane-truth-batch-01 measured 151s red here vs the brief's 355s; bash32
  281s vs 321s. Timings are noisy on this box; each was taken more than once
  where stated, single valid run for lane-truth (the first attempt used
  `env -i` isolation, which broke the fixture's own machinery — invalid
  measurement, discarded, not averaged in).
- Neither gate run reached verdict=PASS: both ended verdict=fail on the same
  three nested suites, attributed above to 2–4 concurrent foreign runners. A
  clean-machine gate run would very likely pass (15/15 in-scope suites pass;
  the three failing ones pass in isolation), but that was not demonstrated —
  this box had foreign lanes live for the entire lane window. The acceptance
  criterion as written (a verdict, not rc=124) is met; a green verdict is
  not among the claims.
- Direction 2 delivered measurements + two proposed rows only — no fix
  applied (not in this lane's write set).
- Both new suites are registered via `# run-all-triggers:` (changed-scope
  selection + DoD registration); neither is added to the wrapper's curated
  full-set SUITE_DEFS — curation of the nightly full set is a lead decision.
- Not merged. No push. The gate verdict below is from THIS machine only.
