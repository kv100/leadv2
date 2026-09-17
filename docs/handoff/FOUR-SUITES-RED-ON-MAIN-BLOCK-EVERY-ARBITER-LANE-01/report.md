# FOUR-SUITES-RED-ON-MAIN-BLOCK-EVERY-ARBITER-LANE-01 — report

Measured 2026-09-17, worktree `3451ac6c2e28` @ base `13fb3dcc`, macOS Darwin 25.6.0, repo
`~/Projects/leadv2`. Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` (read
in full before this lane started work).

## Headline

**Zero allow-list entries removed.** Three of the four suites fail entirely inside off-limits
production files held by the live arbiter lane (`da0acd521f24`,
`ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01`) — attributed below, not fixed here, per the
mission's explicit instruction not to touch them. The fourth, `run-core-offline.sh`, is **not** a
pure timeout: given room to finish (2716s wall against a 580s per-suite ceiling, no suite hit that
ceiling) it completes with `rc=1`, `passed=82 failed=11`. The 420s-budget rc=124 was masking 11
real, already-independently-tracked suite failures, none of which are the other three named in
this mission. That is a fifth finding, named and evidenced below, not repaired here (out of this
lane's scope) — with a recommendation to file it as its own row.

---

## 1. `plugins/leadv2/tests/test-arm-pool-reachability.sh`

**Reproduction:**
```
$ bash plugins/leadv2/tests/test-arm-pool-reachability.sh
```
**Observed (ceiling: suite's own internal 180s wrapper, wall ≈150s, rc=1):**
```
PASS: bash syntax: dispatch
FAIL: (g1) pin fable plan/heavy did not resolve as fable
FAIL: (g1) dispatcher lacks arbiter_pick=fable
PASS: (g1) requested_arm_incapable is gone for a capable (matrix-covered) arm
FAIL: (g1) no launchable_seam source=registry line
FAIL: (g1) capable pin resolves -- rc=1 want=0
FAIL: (g2) --pin-arm alias diverged
FAIL: (g3) pin sonnet capped did not refuse with requested_arm_capped
FAIL: (g3) sonnet:capped token missing
FAIL: (g3) capped pin exits 4 -- rc=1 want=4
FAIL: (g4) explicit pool glm,codex picked 'nothing'
FAIL: (g4) sonnet:not_in_pool missing -- pool is not bounding
FAIL: (g4) explicit pool resolves, rc=0 -- rc=1 want=0
FAIL: (g5) unknown pool member not refused pre-launch
FAIL: (g6) pin_and_pool_conflict missing
FAIL: (g7) incapable fable/code escaped refusal
FAIL: legacy-opus fixture did not reach the pre-arbiter park site
FAIL: explicit --pin-arm opus failed to reach spawn -- rc=8
FAIL: (m1) chain-as-pool mutation did not flip the outcome
PASS: (m3) stripped exit lets the capped pin continue (rc=1), suite is red under it
SUMMARY: pass=3 fail=17
```
Before (mission, 2026-09-16): main rc=1, merged rc=1. After (today): rc=1, pass=3 fail=17, same
shape — unchanged.

**Cause class:** `real_regression`, in a file this lane is forbidden to touch.

**Mechanism, attributed:** the suite drives the real `leadv2-dispatch-code.sh` binary
end-to-end (`DISPATCH_BIN="${PLUGIN_ROOT}/scripts/leadv2-dispatch-code.sh"`, confirmed by
`grep -n DISPATCH_BIN`). Every failing assertion names one of:
- `arbiter_pick=`, `launchable_seam`, `requested_arm_capped`, `requested_arm_not_launchable`,
  `pin_and_pool_conflict` — all emitted from the arbiter branch inside `cmd_resolve()`
  (`leadv2-dispatch-code.sh:8868` onward; the specific `route_resolved by=arbiter` /
  `arbiter_broken reason=fail_open_to_ladder` lines live at `:10153`, `:10156-10186`).
- pool/launchability computation — `_arm_launchable_arms()` (`leadv2-dispatch-code.sh:2924`),
  which embeds the `kind_mapped=` remap (`:2955`) that `ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01`
  is actively rewriting per its own name ("reachable top arms").

Both `leadv2-dispatch-code.sh` and (transitively, via the arbiter it invokes)
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` are named off-limits in this lane's mission —
live lanes hold both. **Attribution: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, function
`cmd_resolve()` (arbiter branch, `:10067-10272`) and `_arm_launchable_arms()` (`:2924-2967`).**

**Verdict:** production code is genuinely exercised and genuinely failing, but the fix lives in a
file this lane may not touch. Left red, named, not a failure of this lane.

**A secondary, separate observation** (not the cause of most failures, but visible in the log): a
handful of dispatch calls in this suite also hit
`premise_probe verdict=refused reason=backlog_row_not_found` before reaching the arbiter at all —
the same `never_reaches_subject` shape the old census named in
`PREMISE-PROBE-BEFORE-A-LANE-IS-DISPATCHED-01`. That refusal is also emitted from
`leadv2-dispatch-code.sh` (off-limits), so it is not actionable from this lane either, and even a
fixture-side `--no-probe-yet` fix would not turn this suite green — the majority of its 17
failures are the arbiter-seam assertions above, which no fixture change touches.

---

## 2. `plugins/leadv2/tests/test-exclusion-stages.sh`

**Reproduction:**
```
$ bash plugins/leadv2/tests/test-exclusion-stages.sh
```
**Observed (ceiling: 180s, wall <10s, rc=1):**
```
PASS: arm_pool=[glm,codex]: fable/sonnet/opus named not_in_pool, winner inside the set
PASS: launchable_arms=[codex,sonnet]: fable is not_launchable but still in the pool -- dimensions do not collapse
PASS: protected code/standard: freepool carries untrusted, winner is a protected-capable arm
PASS: claude at 99%: sonnet:capped typed, the uncapped arm still wins
PASS: healthy auction names its losers price_ratio (in the pool, launchable, trusted, uncapped -- lost on cost)
PASS: several stages on one arm join as not_in_pool+not_launchable (canonical order)
PASS: pin haiku on kind=code (no matrix cell): requested_arm_incapable, rc=69 -- the reserved case
PASS: pin fable (has a plan/heavy cell) refused as requested_arm_not_launchable, never incapable
M2 anchors: stages found 1, order found 0 (expected 1 each) -- re-anchor the control, do not silence it
```
8 of 9 checks pass. Before (mission): main rc=1, merged rc=1. After: rc=1, same shape — unchanged.
(A side finding, not part of the mission ask: this suite's own `_suite_abort_report` diagnostic
trap, set at `test-exclusion-stages.sh:39`, is silently clobbered by the tmpdir-cleanup trap at
`:43` — both register on `EXIT` and bash keeps only the last, so the intended "ABORT: suite exited
without a summary" line never prints on this exact failure path. Noted, not fixed — it is a test
file, not one of the off-limits four, but fixing it is unrelated to this suite's redness and out
of the mission's ask.)

**Cause class:** `real_regression`, but the regression is in the exclusion-stage vocabulary the
live arbiter lane is actively growing — this is exactly a "will resolve when the arbiter lane
lands" case.

**Mechanism, attributed and directly verified:** the suite's mutation control (`M2`, doc comment
at `test-exclusion-stages.sh:158-160`) hard-codes the expected stage list as
`_STAGE_ORDER=['not_in_pool','not_launchable','untrusted','capped','failure_memory','price_ratio']`
and asserts that string appears **exactly once** in
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` before mutating it. The live file, read
directly, now has:
```
$ grep -n _STAGE_ORDER plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
1310:_STAGE_ORDER=['not_in_pool','not_launchable','untrusted','caller_constraint','capped','forecast','failure_memory','price_ratio']
```
Two new stages — `caller_constraint` and `forecast` — have been added inside `route_arbiter()`
(`leadv2-route-arbiter.sh:48`, the exclusion-stage computation at `:1298-1312`) by the in-flight
`ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01` lane. The test's anchor string therefore
matches zero times, its own `sys.exit` fires, and the suite aborts before printing a summary.

**Attribution: `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh:1310`, inside `route_arbiter()`
— off-limits, held by the live arbiter lane.** All 8 substantive (non-control) assertions pass;
only the mutation-control's anchor is stale against the in-flight rewrite.

**Verdict:** will resolve itself once the arbiter lane lands and its stage list stabilizes — at
that point the test's anchor needs a one-line update to the new `_STAGE_ORDER`, which is the
arbiter lane's job (or a trivial follow-up once it merges), not a fix that belongs in this lane.
Ran to believe it: direct `grep` of the live file against the exact string the test requires,
shown above — not a guess.

---

## 3. `plugins/leadv2/scripts/tests/test-arbiter-seam-plugin-kind.sh`

**Reproduction:**
```
$ bash plugins/leadv2/scripts/tests/test-arbiter-seam-plugin-kind.sh
```
**Observed (ceiling: 180s, wall <10s, rc=1, PASS=7 FAIL=8):**
```
PASS: bash syntax: dispatch
FAIL: (g1) no arbiter decision line (route_resolved by=arbiter)
PASS: (g1) no fail_open_to_ladder on the production path
FAIL: (g2) no arbiter decision line (route_resolved by=arbiter)
PASS: (g2) no fail_open_to_ladder on the production path
FAIL: (g2) seam did not answer from the code vocabulary with a kind_mapped line -- guard 1 regressed
PASS: (g3) empty launchable signal still refuses loudly (rc=68 pool_empty_all_excluded)
PASS: (g3) refusal names the not_launchable stage per arm
PASS: (g4) genuinely empty pool still refuses loudly (rc=68)
FAIL: (g5) fail-open line missing or uncounted
FAIL: (g5) day counter did not increment across task signatures
FAIL: (g5) counter day-file not found under suite state root
FAIL: mutation anchor "query_kind = kind if kind in known_kinds else 'code'" found 0 times (expected exactly 1) -- zero-match/ambiguous, hard failure
FAIL: (red) mutation anchor not found -- control not falsifiable -- zero-match
PASS: (red) with the vocabulary coercion reverted, the kind_mapped seam line is gone (suite red under this mutation)
FAIL: (red) guard-2 degradation line absent under guard-1 revert
```
Before (mission): main rc=1, merged rc=1. After: rc=1, PASS=7 FAIL=8 — unchanged.

**Cause class:** `real_regression`, same seam, same held file.

**Mechanism, attributed:**
- `route_resolved by=arbiter` — emitted at `leadv2-dispatch-code.sh:10153` inside `cmd_resolve()`.
- `kind_mapped=` — emitted at `leadv2-dispatch-code.sh:2955` inside `_arm_launchable_arms()`.
- The g5 fail-open counter — `_arb_fail_open_count()` (`leadv2-dispatch-code.sh:2283`) and the
  `arbiter_broken ... reason=fail_open_to_ladder` emission (`:10156-10186`), also inside
  `cmd_resolve()`.
- The suite's own mutation-anchor probe (`query_kind = kind if kind in known_kinds else 'code'`)
  is looking for a specific line inside `_arm_launchable_arms()` and finds it **zero** times —
  the vocabulary-coercion code the arbiter lane is rewriting has already moved or reworded that
  exact line, so the suite's own negative control is unfalsifiable right now (it says so itself:
  "control not falsifiable").

**Attribution: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, functions `cmd_resolve()`
(`:8868-…`, arbiter decision + fail-open lines at `:10153-10186`) and `_arm_launchable_arms()`
(`:2924-2967`) — off-limits, held by the live arbiter lane.**

**Verdict:** same as suite 1 — the production seam is mid-rewrite by a lane this mission forbids
touching. Left red, named, not repaired here. The suite's own mutation control being
unfalsifiable right now is itself evidence of an active rewrite in progress, not a new defect to
chase.

---

## 4. `plugins/leadv2/scripts/tests/run-core-offline.sh` — the different animal

**Question 1 — does it pass given enough time? No.**

Reproduction, run to natural completion with a **580s per-suite ceiling and no artificial outer
wrapper** (the earlier `timeout 590` attempt itself timed out at rc=124 wall=590s — the outer
wrapper, not the per-suite ceiling, was too tight; removing it and letting the runner's own
41-shard/serial structure finish was the correct instrument):
```
$ SUITE_TIMEOUT_S=580 bash plugins/leadv2/scripts/tests/run-core-offline.sh
...
[CORE-OFFLINE] suites passed=82 failed=11 missing=0 known_red_skipped=0 repo=<worktree>
RC=1 WALL=2716s
```
**93 selected, 93 ran, 0 missing, 11 failed, at a 580s per-suite ceiling, wall 2716s (~45 min),
macOS Darwin 25.6.0, worktree `3451ac6c2e28` @ base `13fb3dcc`.** No suite hit the 580s ceiling
(verified: no `timeout`/`rc=124` marker anywhere in the transcript except in unrelated fixture
content about timeout *behaviour*, not the runner's own supervision).

So: **the allow-list entry's comment is only half right.** It correctly says the 420s-budget
`rc=124` is a timeout, not itself an assertion failure. But it is wrong to imply that's the whole
story — underneath that timeout are 11 suites that fail on their own merit, independent of any
budget. Raising the outer budget would not turn this green; it would just let it finish failing
honestly in ~45 minutes instead of being killed at 7.

**Question 2 — what is genuinely red inside it?**

The 11, named by their `[CORE-OFFLINE] FAILED:` label (the runner's own classification, not
sub-case counts) and mapped to their file via `run-core-offline.sh`'s own `SUITE_DEFS` table:

| Label | File |
|---|---|
| lane write-set admission block (LANE-WRITESET-REGISTRY-01) | `test-writeset-admission-block.sh` |
| claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens) | `test-claim-evidence-gate.sh` |
| dispatch arm vocabulary (kimi retirement) | `test-dispatch-arm-vocabulary.sh` |
| phase precondition guard matrix | `test-phase-precondition.sh` |
| plugin reliability (process liveness + role fallback + prepass/reorder signals) | `test-plugin-reliability-01.sh` |
| deferred-GLM ladder (V3-GLM-LADDER-01) | `test-glm-deferred-ladder.sh` |
| review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01) | `test-review-round-exhaustive.sh` |
| dispatch refusal fallback chain | `test-routing-enforcement-p1.sh` (**not** `test-dispatch-refusal-truth.sh` — label-to-file is table-mapped, not name-matched; confirmed by reading `SUITE_DEFS` directly) |
| product-close waits for worker exit | `test-no-work-terminal.sh` |
| lane truth batch (log_path + quarantine convergence) | `test-lane-truth-batch-01.sh` |
| report-only gate (REPORT-ONLY-GATE-01: report lane deliverable) | `test-report-only-gate.sh` |

**None of these 11 is one of the other three suites named in this mission** — `run-core-offline.sh`'s
own curated set does not include `test-arm-pool-reachability.sh` or `test-exclusion-stages.sh`
(different directory, different suite family) and does not name
`test-arbiter-seam-plugin-kind.sh` as failing in this run.

**All 11 are suites already named in the older `MAIN-RED-SUITES-CENSUS-01` / `SD-MAIN-CORE-SUITE-RED-01`
lineage** (`docs/handoff/MAIN-RED-SUITES-CENSUS-01/report.md` and `fix-plan.md`, read at the start
of this lane) — most were dispatched to fix-lanes in that plan, and `test-writeset-admission-block.sh`
specifically was reported there as "green alone... a weaker statement — it may be a fourth
sharding-only red... not established either way." Today's run establishes it: it fails under the
sharded runner. This matches the census's own warning that some suites are
`harness_self_interference` — red only in the environment the runner itself creates, not on their
own merits alone.

At least three of the 11 route through the same two files this mission holds off-limits
(`leadv2-dispatch-code.sh` for the arm-vocabulary/phase-precondition/dispatch-refusal family,
`leadv2-dispatch-product-close.sh` for `product-close waits for worker exit`), so a full root-cause
pass on all 11 would re-enter the same off-limits territory as suites 1–3 above, plus new
1-on-1 diagnosis this mission did not scope for. **Not attempted here — recommendation: file a new
row (e.g. `RUN-CORE-OFFLINE-ELEVEN-RESIDUAL-REDS-01`) rather than fold it into this row's closure,
since it is a distinct population from the four named suites and needs its own per-suite
diagnosis pass.**

**Cause class for the suite `run-core-offline.sh` as named in the allow-list: `timeout` (confirmed,
both at the original 420s budget and at my initial 590s outer-wrapper attempt) **compounding**
`real_regression` (confirmed at 2716s/580s: 11 suites fail on merit once the timeout stops hiding
them).**

**Attribution for the timeout itself:** the 420s figure is not set inside `run-core-offline.sh`
(its own default, via `tests/run-all.sh:130`, is `LEADV2_RUN_ALL_SUITE_TIMEOUT_S=600`); the 420s
budget this row's evidence names comes from whatever invoked it directly with that ceiling in lane
`cdd7a22b`'s kill — likely the e2e gate's own budget cap, which is the explicit subject of the
already-filed, separate row `E2E-GATE-BUDGET-CAP-CONTRADICTS-ITS-OWN-FORMULA-01` (see this repo's
git log, commit `0dabbe77`). Not re-investigated here — it is a named, already-owned row, and
duplicating it would be scope creep.

---

## Allow-list entries removed: NONE, and why that is safe

All four `path:`/`core:`-adjacent entries in `tests/known-red-suites.txt` (lines 92-95) are left
exactly as they are:

- `test-arm-pool-reachability.sh`, `test-exclusion-stages.sh`, `test-arbiter-seam-plugin-kind.sh` —
  still genuinely red, in production files this lane is explicitly forbidden to touch
  (`leadv2-dispatch-code.sh`, `leadv2-route-arbiter.sh`). Removing the entry would be the claim
  that the suite is green; it is not. Left as-is.
- `run-core-offline.sh` — still genuinely red once given time (`rc=1`, 11 failures), not a
  false-timeout. Removing the entry would understate what is actually wrong. Left as-is. The
  entry's comment ("not an assertion failure") is now known to be incomplete — it is a timeout
  **and**, underneath, a real regression — but correcting a comment is not the same claim as
  removing the entry, and the standing rule is explicit: "do not remove an allow-list entry for a
  suite you did not actually repair." None of the four were repaired.

**Removing an entry for a suite you did not fix is exactly the failure mode this row exists to
prevent** — an allow-list entry that outlives its cause is how a red suite becomes permanent, and
the mirror error (removing one that is still causing damage) makes the entry's whole record
untrustworthy. Neither happened here.

---

## Controls

**Control 1 — "a suite you repaired is genuinely repaired": does not apply.** No suite was
repaired in this lane. All three arbiter-seam suites fail inside off-limits production files; the
fourth's real failures (11 suites) belong to a population out of this lane's declared scope. A
mutation control proves a REPAIR detects a regression; there is no repair here to prove, so none is
fabricated. (This is not the same gap as an omitted control — the DoD gate's mutation-control
check applies to a claimed fix; no fix is claimed.)

**Control 2 — "the allow-list still works": RUN, both outputs pasted.**

The mechanism under test is `tests/ci-gate.sh`'s own `is_allowlisted()` function (read directly
from `tests/ci-gate.sh:33-36`), reproduced verbatim against **temp copies** of the real
`tests/known-red-suites.txt` — the live file was never modified (verified with `git status
--short` immediately after, below).

```
$ TMPAL="$(mktemp)"; cp tests/known-red-suites.txt "$TMPAL"
$ ID='path:plugins/leadv2/tests/test-arm-pool-reachability.sh'
$ is_allowlisted() {
    local id="$1" ALLOWLIST="$2"
    [[ -f "${ALLOWLIST}" ]] || return 1
    grep -qxF "${id}" <(grep -vE '^[[:space:]]*(#|$)' "${ALLOWLIST}" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
  }

-- baseline (entry present) --
RESULT: KNOWN (allow-listed)
-- after removing the line from the temp copy --
RESULT: UNEXPECTED (would BLOCK)
-- after re-adding the line --
RESULT: KNOWN (allow-listed)
-- confirm real file untouched --
1
$ git status --short tests/known-red-suites.txt
(empty)
```
Removing the entry (in an isolated copy) is the thing that flips the verdict from KNOWN to
UNEXPECTED (blocking); re-adding it flips it back. The real allow-list file was never written to —
confirmed by `grep -c` finding the original line still present and `git status --short` showing no
diff on it.

---

## Falsification set

No `.sh` or `.py` file was changed by this lane (see diff below), so `bash -n` / `py_compile` have
no changed targets to check. The only new file is this report.

```
$ git status --short
?? docs/handoff/FOUR-SUITES-RED-ON-MAIN-BLOCK-EVERY-ARBITER-LANE-01/report.md
```

Changed-scope test runner, run for completeness even though no code changed:
```
$ tests/run-all.sh --scope changed
```
(output pasted at commit time in the commit body / lane log — expected to select zero suites,
since the only new file is a doc.)

---

## Summary table

| suite | main (2026-09-16) | today (2026-09-17) | ceiling | verdict |
|---|---|---|---|---|
| `test-arm-pool-reachability.sh` | rc=1 | rc=1, pass=3 fail=17 | 180s (suite's own) | red on merit, held file — not repaired |
| `test-exclusion-stages.sh` | rc=1 | rc=1, pass=8 fail=1 (M2 control) | 180s | red on merit, held file — not repaired |
| `test-arbiter-seam-plugin-kind.sh` | rc=1 | rc=1, PASS=7 FAIL=8 | 180s | red on merit, held file — not repaired |
| `run-core-offline.sh` | rc=124 (420s budget) | rc=1, passed=82 failed=11 | 580s per-suite, 2716s wall, no outer cap | timeout WAS masking 11 real, already-tracked reds — not this row's population, recommend new row |

## What was left red, and why

All four. Three because the fix lives in files this lane is explicitly forbidden to touch
(`leadv2-dispatch-code.sh`, `leadv2-route-arbiter.sh` — both held by the live
`ARBITER-SMALLEST-ADEQUATE-AND-REACHABLE-TOP-ARMS-01` lane). The fourth because, once measured
honestly, it turned out to be two problems layered — a timeout that is a separate, already-filed
row's subject (`E2E-GATE-BUDGET-CAP-CONTRADICTS-ITS-OWN-FORMULA-01`), and underneath it 11 named,
independently-tracked residual reds from `MAIN-RED-SUITES-CENSUS-01` that deserve their own
diagnosis pass rather than a rushed fix folded into this row.
