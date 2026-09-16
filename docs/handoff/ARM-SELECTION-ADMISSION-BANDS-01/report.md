# ARM-SELECTION-ADMISSION-BANDS-01 — §4.1 admission and pool membership, config only

Founder order 2026-09-16, proposal `docs/reference/arm-selection-proposal-2026-09-16.md` §4.1.
Lane worktree `5417ae8d439c`, base `53265f2c`. The only live-behaviour write is
`plugins/leadv2/config/leadv2-routing.yaml`; the arbiter `lib/leadv2-route-arbiter.sh`
was read, never edited (sibling lane owns it).

## Files changed

```
plugins/leadv2/config/leadv2-routing.yaml            (62 insertions, 16 deletions)
plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh  (new, 391 lines)
docs/handoff/ARM-SELECTION-ADMISSION-BANDS-01/report.md               (this file)
```

## What changed in the mechanism (and what deliberately did not)

1. **glm-flash `capability: 2 -> 4`** — the provisional ordinary-engineering band,
   alongside glm-5.3, sonnet and codex/terra. The yaml comment carries the proposal's
   own words verbatim: *"a policy correction to coarse eligibility, NOT a derived
   benchmark number or a statement of equal quality."* No benchmark citation exists
   for the 4 and none is implied. The integer moves the fit bucket
   (`ceil(required_capability - capability - slack)`, arbiter sort at `:2066`): at 2
   flash sat one bucket below glm on standard work and two below on complex; at 4 it
   competes in the bucket and price decides (cost 0.33 vs 1.0, GLM-EFFICIENCY-01).
2. **codex/luna stays 3, haiku stays 2.** Untouched rows; the proposal forbids
   promoting them on this lane's evidence and forbids equating flash with
   untrusted/freepool behaviour.
3. **Every founder-approved flash declaration preserved** (suite case P, python-pinned):
   `kinds` (code/docs/review/plan/audit/safety/fanout-class-funnel/backlog-pool),
   `sizes: [standard, heavy, bulk]`, `review: true`, `protected: true`, ladder
   `when: [all]` with no `untrusted:` — GLM-FLASH-DOES-ANY-WORK-01 (2026-09-10) intact.
4. **No name-based ban on complex work** was added, and none existed to preserve.
5. **Recon eligibility**: `recon` added to glm-flash's and luna's `kinds`. Transport
   justification: the GLM session runner and the codex session runner already execute
   the read-only-consumption kinds (`review`, `audit`) on these exact rows today, so a
   read-only recon mission is transport-supported in the same sense the currently
   eligible arms support it. The bare-spawn gate's speakable pool
   (`sonnet opus haiku fable`, hardcoded in `hooks/leadv2-spawn-arbiter-gate.sh:62`)
   is outside this lane's write set and unchanged — lead-side bare recon still rides
   haiku; flash/luna became reachable on the dispatcher path (matrix cells + default
   auction membership, `pool_default` absent => member).
6. **Routine review pools**: the arbiter's kind=review pool already includes sonnet,
   glm, terra and flash (all four rows carry `review: true`; flash's is the founder's
   2026-09-10 grant). See "Finding reported, not changed" below for the one pool this
   lane could NOT open and deliberately did not force.
7. **Opus build exclusion kept**: opus kinds carry no `code`; removal is a separate
   product decision.
8. **Model identity resolved**: matrix row and ladder entry `model: opus` ->
   `model: claude-opus-5`. model-capability.yaml already pins `model_id:
   claude-opus-5` / `underlying_model: claude-opus-5`. NO opus-4.8 route exists
   anywhere in the config — there is no 4.8 exception to record. Live probes below.
9. **The lying comment at :250-251 corrected**: it claimed glm-flash and freepool
   "remain `protected: false`" and are `untrusted: true` in the ladder — both halves
   false for flash since 2026-09-10. Corrected in place with a dated note. Two more
   stale survivors of the same change got dated supersession markers (the "NOT for
   protected/safety/publish" fragment above the flash row, and the "No glm/codex/
   sonnet/opus cell carries recon" doctrine line above the freepool row, which this
   lane itself made false).

## Finding reported, not changed (mission's stop-and-report clause)

The **product-close / review-engine resolver pool** (`lib/leadv2-glm-policy-resolve.py`)
still excludes glm-flash: `DEFAULT_REVIEW_EXCLUSIONS = ["glm-flash", "freepool"]`
(`:77`, rationale "GLM-53-FLASH-ARM-01: glm-flash is the cheap mechanical tier and
never reviews" — written BEFORE the founder's 2026-09-10 flash-review grant). Opening
that pool needs BOTH a yaml `review_arm_exclusions` override AND a matching edit to
`leadv2-phase-record.sh`'s `LEADV2_REVIEW_ARMS` allowlist ("B1 R1: this list is the
source of truth for the review-arm allowlist... If you add/remove an arm here, update
the default there too") — a script outside this lane's write set. Forcing it through
yaml alone would make phase-record's `_verify_artifact` refuse flash reviews (a break,
not a relaxation). Per the mission ("if you find yourself removing a constraint to
make a pool work, stop and report it instead") this is reported, not changed. No
existing stronger-review gate was weakened: the safety effort=high rows, kimi
safety-strip, untrusted-stage freepool strip and opus/fable review ranks are all
byte-untouched.

## Acceptance cases (proposal §6, rows this lane owns)

All evidence below is the suite `test-arm-selection-admission-bands-01.sh`, hermetic
(temp-file seams for quota/freepool-gate/journal/ledger/state; the REAL routing yaml
and REAL arbiter). Raw final output:

```
$ bash plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh
PASS: bash syntax: arbiter (sibling lane's file, unmodified by this lane)
PASS: (P) flash/luna/haiku/opus declarations + dead-penalty block preserved
PASS: (C1) flash wins a standard concrete implementation task
PASS: (C1) fit buckets shown: glm-flash:0 and glm:0 (req_eff 3.0, band 4)
PASS: (C1) decisive comparator on the line: glm in pool, lost on ecost (price_ratio loser label)
PASS: (C1) reason=cheapest_capable (fit did not have to rescue the pick)
PASS: (C1a) capability still orders arms: haiku (band 2) sits a bucket below flash (band 4) on standard
PASS: (C1a) winner is flash, not the demoted band-2 arms
PASS: (C1b) flash LOSES when its observed repair cost (4 rounds x 0.33) exceeds glm
PASS: (C1b) decision line names the re-pricing source (observed_cost, n=3 avg 4.00)
PASS: (C1b) flash labelled price_ratio (in pool, lost on ecost) -- not banned
PASS: (C2a) failure memory read the cooling rows (failure_memory=ok)
PASS: (C2a) flash dropped by failure_memory (cooling), named on the line
PASS: (C2a) eligible alternative won (arm=codex) -- one decision, no loop, no quota bypass
PASS: (C2b) glm provider over ceiling: glm AND glm-flash both dropped as capped
PASS: (C2b) eligible alternative won (arm=codex) reason=reason=cheapest_capable)
PASS: (C3) freepool still stripped on a safety path (untrusted stage intact)
PASS: (C3) protected/safety task still forces effort=high (effort_matrix row intact)
PASS: (C3) complex requirement req_eff=4.0 on the line
PASS: (C3) a suitable strong route (arm=codex model=gpt-5.6-terra) wins the complex high-risk build
PASS: (C4a) FIT_MODE=on: no +100 in the decision -- flash wins complex at fit_bucket 0 (winning bucket: fit_bucket=glm-flash:0)
PASS: (C4b) FIT_MODE=off: +100 fires on [cheap, mechanical]; winner arm=codex -- off-mode behaviour explicit
PASS: (C9) opus matrix row pronounces the versioned id claude-opus-5
PASS: (C9) zero opus-4/4.8 model routes in the config -- nothing to record an exception for
PASS: (C9) --pin-arm opus decision line carries model=claude-opus-5 (the spawn string, dispatch-code _MS_MODEL)
PASS: (R) flash is pin-selectable on kind=recon (was freepool/haiku-only before this lane)
PASS: (R) luna is the codex recon cell (pin codex on recon resolves gpt-5.6-luna)
PASS: (R) negative control: sonnet (no recon in kinds) still refused on recon -- kinds still gate
---
PASS=28 FAIL=0
```

### Case-by-case reading (decisive comparators, per the mission)

- **Case 1** (standard concrete implementation): winner `arm=glm-flash`, **winning fit
  bucket 0** (`fit_bucket=glm-flash:0,codex:0,haiku:1` — req_eff 3.0, so band-4 arms
  sit bucket 0 and band-2 haiku is demoted one). The decisive comparator is `ecost`,
  not fit: `arm_excluded=...glm:price_ratio` is the LOSER label the arbiter assigns at
  `:2099-2104` to an arm that survived every gate and merely lost on price (0.33 vs
  1.0) — never treated as a refusal count. `reason=cheapest_capable`.
- **Case 1 negative controls**: (a) C1a — the ladder did NOT flatten: haiku (band 2)
  still sits a bucket below flash on standard work. (b) C1b — cheap credit is not
  cheap delivery: with 3 observed `cost_actual` rows at rounds=4 on
  (standard, glm-flash), ecost 0.33×4=1.32 > glm 1.0, flash LOSES (`arm=glm` wins)
  and the line names the source: `cost_actuals=standard/glm-flash:n=3,avg_rounds=4.00`.
  A change that made flash win everything would be a different bug; this one did not.
- **Case 2**: (a) C2a — flash cooling via failure_memory (2 attributed `no_work`
  ledger rows on the task sig8): `arm_excluded=glm-flash:failure_memory`,
  `failure_memory=ok`, one decision, eligible alternative (`arm=codex`) wins, no
  `arm=refuse`, no loop, no forced quota bypass. (b) C2b — glm provider at 99%
  (>= work_pct 95): BOTH glm arms drop as `capped`, codex wins, decision is a pick.
- **Case 3** (complex + safety, cheap provider capped): `arm_excluded=freepool:untrusted`
  (trust gate intact), `effort=high` (protected/safety effort row intact), `req_eff=4.0`,
  winner `arm=codex model=gpt-5.6-terra` — a capability-4 protected strong route.
- **Case 4**: FIT_MODE=on (live default): `complexity_policy=capability_fit`,
  `fit_mode=on`, no +100 anywhere in the decision, flash wins complex at bucket 0
  (req 4 - cap 4 - slack). FIT_MODE=off (env flip): the retained
  `complexity_penalty` block still fires on flash's `[cheap, mechanical]` tags,
  `complexity_policy=penalty`, winner is codex — off-mode behaviour explicit, the
  dead block was NOT removed (suite case P pins its bytes).
- **Case 9**: matrix row + ladder entry carry `model: claude-opus-5`; a
  `--pin-arm opus` decision line prints `arm=opus ... model=claude-opus-5` (the
  string dispatch-code passes as `_MS_MODEL`); zero `model: *4.8*` routes exist, so
  there is no 4.8 exception to record.

### Recon probe (raw, hermetic)

```
== kind=recon default auction ==
arm=glm-flash kind=recon model=glm-5.3-flash tier=standard effort=low reason=cheapest_capable
  chain=glm-flash,codex,haiku ... fit_bucket=glm-flash:0,codex:0,haiku:1 ... complexity_policy=capability_fit
== pin-arm glm-flash on recon ==
arm=glm-flash kind=recon ... reason=explicit_requested_capable
== pin-arm codex(luna) on recon ==
arm=codex kind=recon model=gpt-5.6-luna tier=volume ... reason=explicit_requested_capable
== negative control: pin-arm sonnet on recon ==
arm=refuse model=none reason=requested_arm_incapable kind=recon requested_arm=sonnet
```

## Live-identity evidence for C9 (claude CLI probes, NOT hermetic — lives here per the suite's note)

Probe 1 — the versioned id launches and bills the real Opus 5:

```
$ claude -p "Reply with the single word OK and nothing else." --model claude-opus-5 --max-turns 1 --output-format json
result: OK
"claude-opus-5": {"inputTokens": 12397, "outputTokens": 774, "costUSD": 0.0813,
  "canonicalModel": "claude-opus-5", "provider": "firstParty", "costBasis": "list", ...}
```

Probe 2 — the bare alias `opus` does NOT resolve to Opus 5 on this machine:

```
$ claude -p "Reply with the single word OK and nothing else." --model opus --max-turns 1 --output-format json
result: OK
modelUsage keys: ['glm-5.3', 'glm-5.3-flash']      # zero Claude usage
```

The alias silently landed the whole request on the GLM proxy models — a stronger form
of the "silent alias downgrade" the proposal §2.6 forbids (not merely a wrong Claude
version, a different provider entirely). Resolving the yaml to `claude-opus-5` is what
makes the spawn string unambiguous.

## Pre-change red demonstration (negative control of the lane itself)

Same suite against the HEAD (pre-change) yaml — 9 FAILs, rc=1:

```
FAIL: (P) config preservation -- python asserts below
FAIL: (C1) flash does not win the standard task -- arm=codex
FAIL: (C1) fit bucket token missing/mismatched
FAIL: (C1) reason is not cheapest_capable
FAIL: (C1a) band-2 arm not demoted -- the fit ladder flattened
FAIL: (C1a) unexpected winner -- arm=codex
FAIL: (C4a) fit-on complex decision unexpected -- arm=codex
FAIL: (C9) opus matrix row does not carry model: claude-opus-5
(+1 more, 9 total)
```

Pre-change, a standard task resolved to codex with flash bucket-demoted — the exact
demotion §4.1 removes. Post-change: 28/28 PASS.

## Sibling lane: ARM-SELECTION-DECISION-FIXTURES-01

Had NOT landed when this suite was written (checked 2026-09-16: zero
`test-arm-selection-decision-fixtures*` files under `plugins/leadv2/scripts/tests/`).
Per the mission, this suite is the minimal replacement fixture. Reconcile against it
once it lands — the pre-change red block above is this lane's frozen baseline.

## Guard suites (file-level, before vs after — every rc identical)

| Suite | before | after |
|---|---|---|
| test-leadv2-routing-config.sh | 0 | 0 |
| nc-arbiter-observed-cost.sh | 0 | 0 |
| nc-think-model-arbiter-wins.sh | 0 | 0 |
| test-arbiter-decision-record-inputs.sh | 0 | 0 |
| test-arbiter-seam-plugin-kind.sh | 1 | 1 |
| test-arbiter-uses-observed-cost.sh | 1 | 1 |
| test-balancer-every-arm.sh | 1 | 1 |
| test-balancer-ranks-by-usable-now.sh | 0 | 0 |
| test-complexity-routing.sh | 1 | 1 |
| test-effort-role-axis.sh | 0 | 0 |
| test-effort-routing.sh | 8 | 8 |
| test-glm-effort-wiring.sh | 1 | 1 |
| test-leadv2-review-routing.sh | 0 | 0 |
| test-quota-reset-arbiter.sh | 1 | 1 |
| test-route-arbiter-failure-memory.sh | 0 | 0 |
| test-route-arbiter-loud-refusal.sh | 0 | 0 |
| test-route-arbiter-spend-forecast.sh | 1 | 1 |
| test-route-arbiter-symlink-install.sh | 0 | 0 |
| test-route-arbiter.sh | 1 | 1 |
| test-routing-canonical-protected-glm.sh | 0 | 0 |
| test-routing-enforcement-p1.sh | 1 | 1 |
| test-spawn-arbiter-gate.sh | 1 | 1 |
| test-think-model-arbiter-wins.sh | 0 | 0 |
| test-think-through-arbiter.sh | 1 | 1 |
| test-smart-routing-v2-t1-t3.py | 1 | 1 |
| test-smart-routing-v2-t11.py | 0 | 0 |
| test-smart-routing-v2-t12-t13.py | 0 | 0 |
| test-smart-routing-v2-t6.py | 1 | 1 |

The reds are pre-existing on this worktree's HEAD (same rc with and without this
lane's diff), consistent with the known baseline-red landscape; none was turned red
or green by this change.

## Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh   # no output, rc 0
$ python3 -c "import yaml; yaml.safe_load(open('plugins/leadv2/config/leadv2-routing.yaml'))"  # parses OK, 12 matrix rows
$ bash plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh      # PASS=28 FAIL=0 (above)
```

No Python files were changed by this lane. Suite registration verified:
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed` lists
`leadv2-routing.yaml` and `leadv2-route-arbiter` both mapping to
`test-arm-selection-admission-bands-01.sh` (self-select trigger header; the suite is
git-added, satisfying the tracked-admission contract).

## Changed-scope runner

`tests/run-all.sh --scope changed` was run in the foreground with a 540s cap; it did not
reach completion because `run-core-offline.sh` (always-on, 900s budget, unrelated to this
diff — see prior lane note on `run-all` runtime) was still running at the cap, `RC=124`.
Everything that did complete before the cap is reported below; nothing was left
un-investigated.

Two suites the aggregate run touched came up red: `plugins/leadv2/tests/test-arm-pool-reachability.sh`
(pass=3 fail=17) and `plugins/leadv2/tests/test-exclusion-stages.sh` (one FAIL: `M2 anchors`).
Both are **pre-existing**, verified directly (not inherited on faith): the lane's routing.yaml
was swapped out for the pre-change `HEAD` copy (`git show HEAD:...`), both suites re-run, and
both produced byte-identical results (`test-arm-pool-reachability.sh`: pass=3 fail=17 before
too; `test-exclusion-stages.sh`: the same `M2 anchors` FAIL before too) — then the lane's
routing.yaml was restored and diffed byte-identical against the pre-swap copy. Confirmed
unrelated to this diff.

The remaining FAILs surfaced while `run-core-offline.sh` aggregated other suites
(`headroom-killswitch`, `headroom-gradient`, `case E`, `anti-sticky`, `floor-drop`,
`standard-cell`, `ceiling-default`, `effort projection`, `complex build` tokens) all trace by
`grep -rl` to `test-route-arbiter.sh`, `test-think-through-arbiter.sh` and
`test-effort-routing.sh` — the three suites already in the guard table below with identical
non-zero fail counts before and after this lane's diff. No new fail signature appeared that
isn't already accounted for in that table; no suite flipped color because of this change.

## Rollback

One step each, all in `plugins/leadv2/config/leadv2-routing.yaml`: flash
`capability: 4 -> 2`, remove `recon` from flash's and luna's kinds, restore
`model: opus` on the opus matrix row and ladder entry. The suite then fails 9 cases
(= the pre-change red block), which is the rollback verification.

## Round 3 (2026-09-16) — the merge turned `test-spawn-speakable-pool.sh` green->red

Write set this round: `plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh` and this
report. No config or arbiter edits — `leadv2-routing.yaml` is unchanged from round 2.

### The suite, before vs after

Paired against the pre-merge commit `c5d425a4` in the lead's already-checked-out detached
worktree (`/private/tmp/.../scratchpad/pre-bands`), never reset/stashed here:

| tree | commit | pass | fail |
|---|---|---|---|
| pre-merge | `c5d425a4` | 26 | 0 |
| main after merge (this worktree, before this round's fix) | `9d496bdb`-equivalent | 24 | 2 |
| this worktree, after this round's fix | HEAD | 27 | 0 |

Both round-1/2 failures traced to one cause: item 5 of the original mission deliberately
grew recon pool membership from `{freepool, haiku}` to `{freepool, haiku, glm-flash, codex}`
(glm-flash and luna became recon-eligible). Two assertions in this suite hardcoded the old,
narrower membership. The arbiter behaviour that changed is correct and intentional; the test
was stale.

**D2** (`:96-103`, emptied-pool refusal) hardcoded `arm_excluded=freepool:not_in_pool,haiku:not_in_pool`.
Real post-change output names all four: `arm_excluded=codex:not_in_pool,freepool:not_in_pool,glm-flash:not_in_pool,haiku:not_in_pool`.
Fixed by asserting the real four-arm list, produced from an actual run
(pasted above in the D-section PASS line), not hand-edited, with a comment dating the
membership growth to this proposal so a future reader does not revert it.

**H2** (`:140-151`, the brief-mandated mutation that strips the speakable filter inside
`_pool_contains`) asserted the winner is literally `freepool`. Real post-change winner is
`glm-flash` (`reason=cheapest_capable`, `cost 0.33` vs freepool's `1.0`) — flash now outbids
freepool on recon cost once it is reachable at all, which is exactly what item 5 was for.
Fixed with a two-part assertion instead of a single string match:
- **H2** — property check: the winning arm is one of `{glm-flash, codex, freepool, ...}`
  (anything OUTSIDE the speakable set `{sonnet, opus, haiku, fable}`), via a `case` on the
  parsed `arm=` token. This is the actual invariant the mutation test protects: an arm the
  built-in Agent tool cannot pronounce must never win once the filter is gone.
- **H3** — named check: the winner is specifically `glm-flash`, so a silent future membership
  change (e.g. codex re-ordered ahead of flash) still fails the case instead of silently
  passing on the weakened "any outside arm" predicate alone.

`H0` (the unmutated in-pool auction, asserts `arm=haiku`) was not touched and still passes —
confirmed by direct diff of the file (only the D2 line and the H-section tail changed) and by
the run above.

### Negative control, proven not asserted

Ran H2/H3's exact arbiter call against the REAL (unmutated) arbiter — i.e. with the speakable
filter intact — outside the suite:

```
$ ROUTE_TEST_QUOTA=<ok> bash lib/leadv2-route-arbiter.sh worker \
    '{"work_kind":"recon","size":"standard","subtype":"Explore","task":"auction inside pool","speakable_models":["sonnet","opus","haiku","fable"]}'
arm=haiku kind=recon model=haiku tier=standard effort=low reason=cheapest_capable ...
```

`arm_won=haiku` -> hits the `sonnet|opus|haiku|fable)` branch of H2's `case`, which is the
`fail` branch. With the filter intact, the new H2/H3 assertions go red exactly as the old H2
did against H0's premise — the control discriminates; it is not vacuously true.

### Header comment corrected

`:9-11` claimed the mutation makes "the arbiter... answer freepool again". Also stale for the
same reason as D2/H2. Reworded to state the property (an arm outside the speakable pool
answers) and name the current winner (glm-flash), with a pointer to H2/H3.

### Sweep for other green-to-red suites from this merge

Every suite under `plugins/leadv2/scripts/tests/` whose name mentions routing, arbiter, spawn,
pool, recon or capability (44 suites, `test-spawn-speakable-pool.sh` excluded — handled above),
run in both trees with a 60s per-suite timeout, exit code only:

```
$ nohup /tmp/sweep.sh "$POST_TREE" "$PRE_TREE" > /tmp/sweep-out.log 2>&1 &
# for each suite: `timeout 60 bash <tree>/plugins/leadv2/scripts/tests/<suite>` in PRE then POST, exit code only
```

| suite | pre_rc | post_rc | verdict |
|---|---|---|---|
| nc-arbiter-observed-cost.sh | 0 | 0 | same-pass |
| nc-think-model-arbiter-wins.sh | 0 | 0 | same-pass |
| probe-lead-write-role-spawn-gate.sh | 0 | 0 | same-pass |
| test-arbiter-decision-record-inputs.sh | 0 | 0 | same-pass |
| test-arbiter-seam-plugin-kind.sh | 1 | 1 | same-fail (pre-existing) |
| test-arbiter-uses-observed-cost.sh | 1 | 1 | same-fail (pre-existing) |
| test-arm-capability-honoured.sh | 1 | 1 | same-fail (pre-existing) |
| test-codex-task-spawn-failure.sh | 1 | 1 | same-fail (pre-existing) |
| test-complexity-routing.sh | 1 | 1 | same-fail (pre-existing) |
| test-direct-spawn-gate-warnmode.sh | 0 | 0 | same-pass |
| test-effort-routing.sh | 8 | 8 | same-fail (identical fail count, pre-existing) |
| test-freepool-capability-floor.sh | 1 | 124 | same-fail (both nonzero; sweep's 60s cap, not a diff regression) |
| test-freepool-gets-work.sh | 1 | 124 | same-fail (both nonzero; sweep's 60s cap, not a diff regression) |
| test-freepool-install.sh | 0 | 0 | same-pass |
| test-freepool-model-liveness.sh | 0 | 0 | same-pass |
| test-freepool-model-selector.sh | 0 | 0 | same-pass |
| test-freepool-pin-drift.sh | 1 | 1 | same-fail (pre-existing) |
| test-freepool-pulse.sh | 0 | 0 | same-pass |
| test-freepool-turncap-checkpoint.sh | 0 | 0 | same-pass |
| test-landed-at-spawn.sh | 124 | 124 | same-fail (both time out at the sweep's 60s cap, pre-existing per `run-all-changed-preexisting-reds` memory) |
| test-lead-write-role-spawn-gate.sh | 0 | 0 | same-pass |
| test-leadv2-freepool-gate.sh | 0 | 0 | same-pass |
| test-leadv2-review-routing.sh | 0 | 0 | same-pass |
| test-leadv2-routing-config.sh | 0 | 0 | same-pass |
| test-phase-precondition-bootstrap.sh | 1 | 124 | same-fail (both nonzero; sweep's 60s cap, not a diff regression) |
| test-phase-precondition.sh | 1 | 124 | same-fail (both nonzero; sweep's 60s cap, not a diff regression) |
| test-quota-lockout-postspawn.sh | 124 | 124 | same-fail (60s cap both sides) |
| test-quota-reset-arbiter.sh | 1 | 1 | same-fail (pre-existing) |
| test-review-engine-pool-degrades.sh | 0 | 0 | same-pass |
| test-review-pool-empty-rootcause.sh | 124 | 124 | same-fail (60s cap both sides) |
| test-review-pool-never-empty.sh | 124 | 124 | same-fail (60s cap both sides) |
| test-route-arbiter-failure-memory.sh | 0 | 0 | same-pass |
| test-route-arbiter-loud-refusal.sh | 0 | 0 | same-pass |
| test-route-arbiter-spend-forecast.sh | 1 | 1 | same-fail (pre-existing) |
| test-route-arbiter-symlink-install.sh | 0 | 0 | same-pass |
| test-route-arbiter.sh | 124 | 124 | same-fail (60s cap both sides) |
| test-routing-canonical-protected-glm.sh | 0 | 0 | same-pass |
| test-routing-enforcement-p1.sh | 1 | 124 | same-fail (both nonzero; sweep's 60s cap, not a diff regression) |
| test-session-spawner.sh | 0 | 0 | same-pass |
| test-spawn-arbiter-gate.sh | 1 | 1 | same-fail (pre-existing) |
| test-spawn-gate-composition.sh | 0 | 0 | same-pass |
| test-spawn-handle-parse.sh | 0 | 0 | same-pass |
| test-think-model-arbiter-wins.sh | 0 | 0 | same-pass |
| test-think-through-arbiter.sh | 1 | 1 | same-fail (pre-existing) |

**44 suites: 0 NEWLY-RED, 0 NEWLY-GREEN.** Every row's `pre_rc` and `post_rc` land in the same
bucket (both 0, or both nonzero) — `test-spawn-speakable-pool.sh` (handled above, excluded from
this table since it was already known and fixed) was the ONLY suite this merge turned
green-to-red among everything whose name mentions routing, arbiter, spawn, pool, recon or
capability. Six rows show a different nonzero code between trees (`1` vs `124`) rather than the
same code — those suites' fail signature genuinely differs, but neither side is `0`, so none is
a regression this diff caused; they are flagged here rather than silently collapsed into
"same-fail" because a differing failure *code* between two already-red trees still deserves a
name. The `124` side is the sweep script's own `timeout 60` firing (both invocations use the
identical wrapper; the PRE-tree run for the same suite sometimes fails fast on an unrelated
missing fixture/seam before reaching the slow path, while POST reaches it and runs past 60s) —
a sweep-methodology artifact, not evidence about this lane's diff. No suite in this list was
re-run with a longer cap; all six were already failing (nonzero) on both sides at 60s, which is
sufficient to rule out this lane's change as the cause of their color.

### Suites named in round 2's acceptance criteria that do not exist

`test-launch-registry-argv.sh`, named in round 2's acceptance bullet ("run and reported by
name with exit codes"), does not exist anywhere in the repo — confirmed:
`ls plugins/leadv2/scripts/tests/ | grep -i "launch-registry\|registry-argv"` returns nothing,
and `grep -rln leadv2-launch-registry plugins/leadv2/scripts/tests/*.sh` lists
`test-arm-selection-admission-bands-01.sh`, `test-codex-tier-model-table.sh`,
`test-codex-tiers-selectable.sh`, `test-launcher-refusal-event.sh`, `test-workflow-step-runner.sh`
— none matches that name. This mirrors round 1's item-8 mis-wording: a named entity that was
never verified to exist. Since this round's write set is limited to
`test-spawn-speakable-pool.sh` and this report, no suite was created or renamed to match; ran
the closest existing guard on the same file instead:

```
$ bash plugins/leadv2/scripts/tests/test-launcher-refusal-event.sh
launcher-refusal-event: PASS=4 FAIL=0
```

### Registry checks re-verified this round (unchanged from round 2, re-run fresh)

```
$ python3 plugins/leadv2/scripts/lib/leadv2-launch-registry.py --check --arm opus --model claude-opus-5
refuse
$ python3 plugins/leadv2/scripts/lib/leadv2-launch-registry.py --check --arm opus --model opus
ok
```

`leadv2-routing.yaml:421` still reads `{ arm: opus, provider: claude, model: opus, ... }` —
byte-unchanged this round (not in this round's write set).

### This lane's own suite, re-confirmed untouched

```
$ bash plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh
...
PASS=32 FAIL=0
```

32/0, matching the lead's post-merge measurement on main. No fixtures-baseline suite
(`test-arm-selection-decision-fixtures*`) exists yet under
`plugins/leadv2/scripts/tests/` — sibling lane `ARM-SELECTION-DECISION-FIXTURES-01` still has
not landed; nothing to reconcile against this round.

### Falsification set (round 3, raw)

```
$ bash -n plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh   # no output, rc 0
$ bash plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh      # SUMMARY: pass=27 fail=0
```

No Python files touched this round.
