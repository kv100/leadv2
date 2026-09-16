# WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01 — lane report

Worker lane `f194017d28c4` · branch `worktree-f194017d28c4` · base `e1baab7c`
Platform: macOS Darwin 25.6.0 (bash 3.2.57). All measurements on this tree, 2026-09-16,
arbiter `arb_rev` 31f2e713e00d (before) → a488efe537bf (after).
Write set honoured: arbiter + 3 suites + this report. `probe.sh` untouched.
Provenance note: a mid-run session loss left the arbiter fix reverted on disk (parallel
write-back); it was restored byte-identically (sha1 `aab894e6…`) and every number in this
report was re-measured on the restored tree on resume, 2026-09-16.

## 1. The defect (measured, on the probe fixture)

`reset_urgency_weight()` in `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` scored
`best = max(score)` over **every readable window** — five_hour included. A five-hour bucket
0.2 h from reset yields weight `0.8 + 1.2·(1 − 0.2/5.0) = 1.024` → urgency 1.816, which
divided codex's ecost enough to beat glm despite the weekly allocation key (weekly 40 %
glm vs 45 % codex) favouring glm. Boundary of the evidence: this is a constructed hermetic
fixture inside `probe.sh` (the founder-measured instance was `codex:1.816[five_hour]` in
the wild); no claim about production decision rates is made here.

## 2. Probe before/after (raw decision lines)

`bash docs/handoff/WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01/probe.sh`

BEFORE (pre-diff arbiter, measured on this tree at base; rc=1, RED):

```
arm=codex kind=code model=codex tier=standard effort=medium reason=cheapest_capable chain=codex,glm util_glm=40 util_codex=45 util_claude=10 util_freepool=100 reset_glm=100.00h_live reset_codex=100.00h_live reset_claude=5.00h_default_full_period reset_freepool=n/a headroom_w=0.64 usable_now=0.55 headroom_priced=codex:0.64,glm:0.68 claude_account_state=ok claude_probe_penalty=0 claude_priced_from=measured arm_excluded=glm:price_ratio arb_rev=31f2e713e00d matrix_rev=d5879ad986be floor_mode=bulk_only floor_mode_source=default test_only=0 complexity=unknown duration_class=unknown complexity_policy=none remaining=55.0 reset_in=100.00h reset_basis=live failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=off fit_pick=codex fit_differs=0 fit_bucket=codex:0,glm:0 cap_default=codex,glm reset_urgency=codex:1.816[five_hour],glm:1.243[weekly] caller_min_cap=none caller_max_cost=none cost_src=codex:measured role=none
RED: glm did NOT win -- the expiring five-hour bucket decided  (probe rc=1)
```

AFTER (re-run 2026-09-16 on this tree, post-diff; rc=0, GREEN):

```
arm=glm kind=code model=glm-5.3 tier=standard effort=low reason=cheapest_capable chain=glm,codex util_glm=40 util_codex=45 util_claude=10 util_freepool=100 reset_glm=100.00h_live reset_codex=100.00h_live reset_claude=5.00h_default_full_period reset_freepool=n/a headroom_w=0.68 usable_now=0.6 headroom_priced=codex:0.64,glm:0.68 claude_account_state=ok claude_probe_penalty=0 claude_priced_from=measured arm_excluded=codex:price_ratio arb_rev=a488efe537bf matrix_rev=d5879ad986be floor_mode=bulk_only floor_mode_source=default test_only=0 complexity=unknown duration_class=unknown complexity_policy=none remaining=60.0 reset_in=100.00h reset_basis=live failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=off fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0 cap_default=codex,glm reset_urgency=codex:1.223[weekly],glm:1.243[weekly] caller_min_cap=none caller_max_cost=none cost_src=glm:measured role=none
GREEN: glm won (weekly reserve decided)  (probe rc=0)
```

What moved: `reset_urgency=codex:1.816[five_hour]` → `codex:1.223[weekly]` (the five-hour
term is gone; codex is now priced by its weekly window), and the decision flipped to glm
(`arm_excluded` follows). `headroom_priced=codex:0.64,glm:0.68` is unchanged — in this
fixture neither arm's headroom crossed the long-window rule differently, so the flip is
attributable to the urgency term alone. (`effort=low` is glm's provider effort projection,
`remaining` 55→60 follows the winner's weekly remainder.)

## 3. Where admission happens now (mission point 2)

The five-hour window keeps its full admission job — **filter/defer, not down-weight** — in
the pre-score stage ladder (`_STAGE_ORDER`, arbiter ~:1257), all evaluated **before** ecost
pricing:

- `capped` — `util()`'s binding window pct ≥ ceiling; a five_hour over the work ceiling
  excludes the arm outright (`arm_excluded=<arm>:capped`).
- `forecast` — fit-vs-remainder on **every readable window** (five_hour included) plus the
  near-reset wait `_forecast_wait` (`WAIT_FRACTION_OF_PERIOD=0.10`; for a 5 h period that
  is a 0.5 h deferral window).
- `near_reset_wait` — the deferral cliff itself.

This diff removes five-hour state from exactly the two **ranking** terms
(`reset_urgency_weight`'s max-loop and `headroom_weight`'s domain) and touches none of the
cliffs. Why filter rather than a small weight: any weight, however small, still lets
five-hour state answer "who deserves this task", which the founder order forbids; a cliff
answers only the boolean "can this arm take work right now", which is exactly the question
admission owns. Pinned by the new "edge five-hour still admits" case in
test-headroom-continuous.sh (five_hour 99 % → `sonnet:capped` while weekly is healthy).

## 4. Point 3 — what `headroom_weight`'s short-window branch does now

**Retired, not rescaled.** The `_headroom_ramp(usable_now)` rate ramp is deleted;
`_long_window(key)` replaces it: the worst (max-used) readable window with
`period >= _HEADROOM_LONG_PERIOD_HOURS` prices the THE-BALANCER remaining-fraction reserve
`w = 0.2 + 0.8·(100−pct)/100`. The documented `usable_now` per-hour incomparability trap is
moot for ranking: `usable_now` enters no ranking term any more (it stays on the render line
as telemetry only). Arms with **no** readable long window (freepool; test-fixture `primary`)
are neutral 1.0 and named loudly via `headroom_unknown=no_long_window` — not silently
floored. THE-BALANCER's reserve is now the *only* headroom ranking signal, and its own
suite (period-invariant (a)(b)(c)) still passes untouched.

## 5. Point 4 — founder constants, before/after (nothing silently rescaled)

| constant | before | after | note |
|---|---|---|---|
| `_HEADROOM_U_SAT` | `8.0` | **deleted** | it was the ramp's saturation point; the ramp is gone, so the constant would be dead. Deletion documented in-code. |
| `_HEADROOM_W_MIN` | `0.2` | `0.2` | meaning unchanged — reserve lower bound (unmetered floor) |
| `_HEADROOM_W_MAX` | `1.0` | `1.0` | meaning unchanged — reserve upper bound |
| `_RESET_URGENCY_W_MIN` / `_MAX` | `0.8` / `2.0` | `0.8` / `2.0` | formula line byte-identical (it is the (i) control's anchor); only the domain narrows to long windows |
| `_HEADROOM_LONG_PERIOD_HOURS` | `24.0` | `24.0` | **value unchanged, meaning widened**: now also gates `reset_urgency_weight`'s window loop (recorded in the THE-BALANCER comment tail) |

## 6. The three suites (before → after, every changed case justified)

Boundary for all numbers: this tree, base `e1baab7c` vs post-diff working tree, macOS
Darwin 25.6.0, 2026-09-16. Before-counts re-measured from HEAD bytes (suite + arbiter
extracted via `git show`), not remembered.

| suite | before | after | wall |
|---|---|---|---|
| `test-reset-urgency.sh` | pass=10 fail=0 | pass=12 fail=0 | 2.97 s |
| `test-headroom-period-invariant.sh` | pass=6 fail=0 | pass=6 fail=0 | 1.86 s |
| `test-headroom-continuous.sh` | pass=6 fail=3 (as committed); 9/9 with journal pinned | 12 passed, 0 failed | 4.36 s |

- **test-reset-urgency.sh — case (e) rewritten.** Cause class
  `test_encodes_superseded_requirement`: until 2026-09-16 it asserted
  `reset_urgency=claude:1.760[five_hour]` + `arm=sonnet` — that an expiring five-hour bucket
  *buys* the arm. Superseded by founder order WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01
  (2026-09-16); the decision is recorded in the arbiter's D1 comment, and the new pin is
  the new-behaviour guard: `arm=codex`, `reset_urgency=claude:1.229[seven_day]`, and **no
  `[five_hour]` token at all**. Case **(j) added** as the filter's negative control (below).
- **test-headroom-period-invariant.sh — case (d) rewritten.** Same cause class: the old pin
  was "five_hour rides the rate ramp unchanged (0.6)" — a five-hour rate as *preference*;
  the new pin is burnt (80 %) vs fresh (10 %) five_hour both pricing `glm:0.92` from weekly
  alone. THE-BALANCER's own cases (a)(b)(c) untouched and green. Case **(e)** mutation
  anchor moved into the new body (reserve formula → constant 0.5); RED spread 0.0, GREEN
  spread 0.528.
- **test-headroom-continuous.sh — full rewrite.** The 2026-09-10 suite pinned the ramp's
  acceptance facts; the order deleted the ramp, so every acceptance fact is re-pinned in its
  post-2026-09-16 form (cause class `test_encodes_superseded_requirement`, recorded in the
  suite header and the arbiter comments): separation, an 11-point monotonicity sweep
  (0..90 — at ≥95 the binding window crosses the `capped` cliff before pricing, so no
  weight exists to sample; that boundary is case 3c's), founder pair, weekly-0 % edge (no
  headroom token + `headroom_w=1` — the winner-setdefault only fires when another arm was
  priced), five-hour neutrality, five-hour-still-admits, unmetered floor, discrete
  refusals, no-dead-key, mutation control. The 3 baseline reds were **not** this diff:
  cause class `environment_dependent` — the old suite read the host's live journal
  (`~/.claude/cache/leadv2-events/leadv2.jsonl`, forecast p75 from 202 live durations,
  cost_actuals n=4/n=5); pinning `LEADV2_ROUTE_ARBITER_EVENTS_JOURNAL` to an empty file on
  the **old** code gave 9/9. The rewrite pins the empty journal in-suite (the arbiter
  documents the seam, ~:137).

## 7. Negative controls — one per independent claim, RED and GREEN in-suite

| claim | control | mutation (inside changed body) | RED | GREEN |
|---|---|---|---|---|
| urgency is the weekly-scale window's proximity (formula) | reset-urgency (i), pre-existing | `weight=_RESET_URGENCY_W_MIN+…*best` → `weight=_RESET_URGENCY_W_MIN` | founder case flips to codex | sonnet restored |
| the long-window **filter** keeps five-hour out of urgency | reset-urgency (j), **new** | `if period<_HEADROOM_LONG_PERIOD_HOURS:` → `if False:` | `(e)` fixture flips back to `arm=sonnet`, `claude:1.760[five_hour]` | codex, no `[five_hour]` token |
| headroom = weekly reserve formula (the spread) | period-invariant (e), anchor updated | reserve two lines → `_w=0.5` | spread collapses 0.528 → 0.0 | 0.528 restored |
| headroom's long-window filter bars the five-hour rate | continuous suite mutation, **new** | `if _period is None or _period<_HEADROOM_LONG_PERIOD_HOURS: continue` → `if _period is None: continue` | claude prices 0.84 from five_hour | 0.92 from weekly |

Each control mutates a private copy of the arbiter (anchor-count asserted = 1) and both the
RED and GREEN verdicts are PASS lines in the suite output (the artifacts).

## 8. `fit_mode` shadow observations (reported, NOT flipped)

- Probe (hermetic config, no fit block): `fit_mode=off fit_pick=glm fit_differs=0
  fit_bucket=glm:0,codex:0` — shadow agrees with the live pick after the fix (pre-diff run
  also showed `fit_differs=0`, pick codex then, glm now: the shadow tracks the decision,
  it does not dissent).
- Live config `plugins/leadv2/scripts/config/leadv2-routing.yaml:499` has
  `capability_fit.enabled: true` (production runs `fit_mode=on`; the continuous-suite
  baseline line on the live config showed `fit_mode=on`).
- This diff does not touch any fit code path.

## 9. Adjacent impact and left-red list (outside this lane's write set)

Changed-scope runner (`tests/run-all.sh --scope changed`) selected 46 suites: **22 passed,
23 failed, 1 known-red-skipped** (raw tail in §11). Every red was re-measured against the
**base arbiter bytes** (`git show HEAD:…route-arbiter.sh`, brief swap, sha1-verified
restore) to separate pre-existing reds from diff-caused ones. Boundary: same tree, same
day, suites run one-by-one; `run-core-offline.sh` (the 23rd red) was NOT re-measured on
base — per the concurrent-runner memory a second live lane (`LEADV3-PARITY-SKILLS…`,
phase=build) flips its nested lock/codex/glm suites, and it does not grep the two changed
functions.

**20 of 23 reds are pre-existing on base** (identical or worse rc/counts on the pre-fix
arbiter): arm-pool-reachability 3/17, exclusion-stages, arbiter-seam-plugin-kind,
arbiter-uses-observed-cost 11/1, arm-admission 13/5, arm-capability-honoured,
complexity-routing 7/5, effort-routing rc=8, freepool-capability-floor 21/12,
freepool-gets-work 1/9, glm-flash-arm 12/8, glm-review-and-ceiling-95 7/1,
quota-reset-arbiter 7/2, route-arbiter-spend-forecast 7/2, spawn-arbiter-gate 27/1,
t13-slice2 14/1 (documented baseline red), launch-uses-chosen-arm rc=2,
router-v2-capability-fit rc=2 (FATAL `effort_scale must be a non-empty list` — config
fixture defect, base=rc2), arbiter-reads-capability-floor 5/1.

**3 suites have new reds vs base — all the SAME cause class, all outside the write set:**

- `test-route-arbiter.sh`: base 25/7 → after 24/8. The one new red is case (d) anti-sticky
  (bulk rotation across glm/freepool): the fixture has glm weekly 70 % used; pre-diff glm's
  headroom was neutral 1.0 (`no_usable_now` path), post-diff glm prices reserve 0.44 while
  freepool stays neutral — the fixture's accidental price tie broke. Cause class
  `test_encodes_superseded_requirement`. Rotation *mechanism* intact: with the tie restored
  (glm weekly 0 %), three consecutive runs rotate glm → freepool → glm.
- `test-think-through-arbiter.sh`: base 15/0 → after 14/1. "floor-drop" case expected
  `heavy -> glm`; now answers `astra`. Decision row (measured): pre-fix glm priced exactly
  1.0 via the five-hour-saturated ramp (fixture glm five_hour 10 % → usable_now 18 ≥ SAT);
  post-fix glm's weekly 10 % reserve = 0.92 → ecost 1.087, the codex-family tie at 1.0
  (astra/codex/sol, no readable long window → neutral) wins and `capability_fit` picks
  astra (capability 6). Same superseded premise ("glm is cheapest at healthy quota" was a
  ramp artifact).
- `test-router-v2-shadow-mode.sh`: base 10/0 → after 5/5. §9.2 rows r1/r2/r3/r6 pinned
  actual `arm=glm`; now r1–r3 pick glm-flash (0.33/0.92 = 0.359 beats glm 1.087) and r6
  picks astra — the shadow-vs-off invariance itself still holds on every row (the failing
  token is the pinned arm, not `actual_arm != off_arm`).

All three need re-pinning to post-order winners in a follow-up lane (write set here is
fixed). `test-decision-record-inputs.sh`: 6/0 green after the diff (measured).
Stale comments in `leadv2-routing.yaml:68` and `:201` still describe the five-hour ramp —
outside the write set, left untouched.
Separately-owned twin row `7ea4fed65451` (account picker): no code shared; concept
coordination only — the "weekly allocates, five-hour admits" split is now stated in the
arbiter's D1/founder-order comments for that lane to consume.

## 10. Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh ; echo rc=$?
rc=0
$ bash -n plugins/leadv2/scripts/tests/test-reset-urgency.sh ; echo rc=$?
rc=0
$ bash -n plugins/leadv2/scripts/tests/test-headroom-period-invariant.sh ; echo rc=$?
rc=0
$ bash -n plugins/leadv2/scripts/tests/test-headroom-continuous.sh ; echo rc=$?
rc=0
```

`python3 -m py_compile`: **no Python files changed** — the arbiter embeds its Python inside
the `.sh` (covered by `bash -n` for shell syntax); the embedded Python is exercised
end-to-end green by all three suites and the probe.

Changed-scope runner (`tests/run-all.sh --scope changed`, run after the foreign lane
`f11c97a14f88`'s own run-all drained, per the concurrent-runner memory): raw tail in §11.

## 11. Changed-scope runner (raw output)

`bash tests/run-all.sh --scope changed` (2026-09-16, this tree, post-diff; run after the
foreign lane `f11c97a14f88`'s own run-all drained, per the concurrent-runner memory):

```
run-all: 22 passed, 23 failed, 0 known-red (allow-listed, non-blocking), 1 known-red-skipped (budget mode, still run by --scope all), 0 gone-green (remove from allow-list), scope=changed
```

The 23 `[FAIL]` suites (paths relative to repo root): run-core-offline.sh ·
test-arm-pool-reachability.sh · test-exclusion-stages.sh · test-arbiter-seam-plugin-kind.sh ·
test-arbiter-uses-observed-cost.sh · test-arm-admission.sh · test-arm-capability-honoured.sh ·
test-complexity-routing.sh · test-effort-routing.sh · test-freepool-capability-floor.sh ·
test-freepool-gets-work.sh · test-glm-flash-arm.sh · test-glm-review-and-ceiling-95.sh ·
test-quota-reset-arbiter.sh · test-route-arbiter-spend-forecast.sh · test-route-arbiter.sh ·
test-spawn-arbiter-gate.sh · test-t13-slice2.sh · test-think-through-arbiter.sh ·
test-launch-uses-the-chosen-arm.sh · test-router-v2-capability-fit.sh ·
test-router-v2-shadow-mode.sh · test-arbiter-reads-capability-floor.sh

Base-vs-after re-measurement of the 22 greppable reds (base arbiter bytes swapped in,
sha1-verified restore to `aab894e6` after):

```
BASE test-arm-pool-reachability.sh      rc=1  pass=3  fail=17   | AFTER rc=1 3/17   pre-existing
BASE test-exclusion-stages.sh           rc=1                  | AFTER rc=1       pre-existing
BASE test-arbiter-seam-plugin-kind.sh   rc=1                  | AFTER rc=1       pre-existing
BASE test-arbiter-uses-observed-cost.sh rc=1  pass=11 fail=1   | AFTER rc=1 11/1  pre-existing
BASE test-arm-admission.sh              rc=1  PASS=13 FAIL=5   | AFTER rc=1 13/5  pre-existing
BASE test-arm-capability-honoured.sh    rc=1                  | AFTER rc=1       pre-existing
BASE test-complexity-routing.sh         rc=1  pass=7  fail=5   | AFTER rc=1 7/5   pre-existing
BASE test-effort-routing.sh             rc=8                  | AFTER rc!=0      pre-existing
BASE test-freepool-capability-floor.sh  rc=1  21 passed 12 failed | AFTER rc=1 21/12 pre-existing
BASE test-freepool-gets-work.sh         rc=1  pass=1  fail=9   | AFTER rc=1 1/9   pre-existing
BASE test-glm-flash-arm.sh              rc=1  pass=12 fail=8   | AFTER rc=1 12/8  pre-existing
BASE test-glm-review-and-ceiling-95.sh  rc=1  pass=7  fail=1   | AFTER rc=1 7/1   pre-existing
BASE test-quota-reset-arbiter.sh        rc=1  pass=7  fail=2   | AFTER rc=1 7/2   pre-existing
BASE test-route-arbiter-spend-forecast.sh rc=1 pass=7 fail=2   | AFTER rc=1 7/2   pre-existing
BASE test-route-arbiter.sh              rc=1  pass=25 fail=7   | AFTER rc=1 24/8  +1 DIFF (see §9)
BASE test-spawn-arbiter-gate.sh         rc=1  pass=27 fail=1   | AFTER rc=1 27/1  pre-existing
BASE test-t13-slice2.sh                 rc=1  PASS=14 FAIL=1   | AFTER rc=1 14/1  pre-existing
BASE test-think-through-arbiter.sh      rc=0  15 pass 0 fail   | AFTER rc=1 14/1  +1 DIFF (see §9)
BASE test-launch-uses-the-chosen-arm.sh rc=2                  | AFTER rc!=0      pre-existing
BASE test-router-v2-capability-fit.sh   rc=2                  | AFTER rc=2       pre-existing
BASE test-router-v2-shadow-mode.sh      rc=0  pass=10 fail=0   | AFTER rc=1 5/5   +5 DIFF (see §9)
BASE test-arbiter-reads-capability-floor.sh rc=1 5 passed 1 failed | AFTER rc=1 5/1 pre-existing
```

The three DIFF suites are outside the write set; cause class and measured decision rows in
§9. The five changed-scope suites this lane owns are all green (reset-urgency 12/0,
period-invariant 6/0, continuous 12/0) or untouched-and-green (decision-record-inputs 6/0).
