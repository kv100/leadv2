# ARM-SELECTION-COST-QUOTA-TELEMETRY-01 — report

Lane owns `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` only, per
`docs/reference/arm-selection-proposal-2026-09-16.md` §4.2-§4.4 and §5. Four
changes, each with its own control; reconciled against the frozen baseline
from `ARM-SELECTION-DECISION-FIXTURES-01`.

## 1. §4.2 — cost provenance

`router_v2.cost` entries may now be a bare number (legacy, byte-identical
behavior) or a mapping `{value, source, observed_at, sample_count,
confidence}`. Only `value` feeds `ecost()`; the rest is diagnostic-only,
surfaced through `cost_src` on the winner's decision line
(`cost_conf=`/`cost_n=`/`cost_at=`/`cost_prov=`, each emitted only when
present).

Key resolution now tries, in order: `provider.model.effort`,
`provider.model`, then the existing provider/arm key
(`_price_key_candidates`) — first candidate present in `router_v2.cost`
wins; an absent candidate is skipped, never treated as a zero price. Today's
sparse live config (glm-flash/glm/freepool only) resolves through the last
candidate exactly as before — no yaml edit required for this to be a no-op
on the live routing config.

**The separator is `.`, not `:`.** The stdlib YAML-subset loader
(`_map_entry`/`_flow_value`, arbiter :297-343) accepts only keys matching
`[A-Za-z0-9_.-]+` and explicitly refuses quoted or colon-bearing keys. A
colon-joined key (`provider:model`) would type-check under real PyYAML but
silently never match under the subset loader this repo ships as its
fallback — that mismatch was caught while writing this lane's own test
fixtures (a `"provider:model": N` fixture failed to parse) and fixed before
it could reach the live config.

An unpriced entry (`null`) is excluded from `_cost_numeric` entirely (never
coerced to 0 or disguised as measured); `provider_cost()` falls back to the
existing matrix-median policy, and `_cost_src()` names it `:median` — or
`:unpriced_all` if no price in the whole config is known — never
`:measured`. `_observed_rounds` was not touched; no second rounds multiplier
was added. NNLS/provider-drain inference was not re-run (out of scope,
explicitly forbidden by the proposal).

**Control:** `test-arm-selection-cost-quota-telemetry-01.sh` A1-A4 — a
dict-shaped cost entry's full metadata reaches `cost_src` (A1); a
plain-number entry stays `:measured` with no metadata tokens, proving the
dict branch is additive (A2); a null-priced winner reads `:median`, never
`:measured` (A3); a `provider.model` key is preferred over the coarser
provider-level key (A4).

## 2. §4.3 — quota: Fable's scoped window no longer replaces the general weekly

`leadv2-route-arbiter.sh:790` (pre-change) did `windows.pop('seven_day',
None)` once a Claude arm's own `weekly_scoped` window was found: the scoped
reading **replaced** the account's general weekly aggregate for that arm.
This was the 0485 lane's (`FABLE-IS-PRICED-FROM-A-WINDOW-IT-DOES-NOT-BURN-01`,
2026-09-13) own deliberate, mutation-tested design, reasoned from two live
probes where the scoped reading alone explained observed behavior. This
lane's mission states the founder's contrary claim (Fable draws down BOTH
meters simultaneously) as "a source-level finding, not a proven live
defect — verify before fixing it." Lacking live Anthropic API access to
settle which premise is correct, and facing direct evidence for the OLD
design, this was escalated via the async question channel rather than
decided unilaterally:

- `leadv2-ask.sh` qid=`q-d19ae6cb`, task `dispatch-dacaf22f`, options: (a)
  keep current replace-semantics (0485 stands, leave `:790` alone) vs (b)
  keep both windows as independent binding constraints (apply the
  proposal's fix). Declared default: (a).
- Timed out; `LEADV2_ASK_TIMEOUT_ARCHITECT` adjudicated **option b**,
  overriding the declared default. Implemented accordingly; the arbiter
  comment at the fix site cites the qid for audit.

The fix: `windows.pop('seven_day', None)` is deleted. `seven_day` stays in
`windows` alongside `weekly_scoped:<label>` and `five_hour`; the existing
worst-of-readable-windows binding rule (never a sum, never a replace) now
prices a scoped arm by whichever of its three windows is worst. The five-hour
shared-session window was already correct and is unchanged. Stale/expired
readings (`hours_to_reset=0`) were already excluded from urgency computation
by pre-existing code, unmodified by this change.

**Control:** `test-arm-selection-cost-quota-telemetry-01.sh` B1/B2 — B1:
scoped window free (0%) but general weekly exhausted (97%) → fable is now
excluded/capped (previously silently admitted). B2 (control): scoped
exhausted, general free → fable stays capped on its own window either way,
proving the fix didn't just flip capped→admitted globally.

## 3. §4.4 — rotation no longer trades fitness for variety

`alternatives=[c for c in ok if ecost(c)==price and c['arm']!=last]` picked
ANY equal-ecost, non-`last` arm — with `FIT_MODE=on`, two arms can share
`ecost` while sitting in different fit buckets (`ecost` is provider-priced;
`fit_bucket` is capability-vs-requirement; nothing ties them together), so
rotation could demote the winner to a worse fit purely to avoid repeating
`last`. Verified reproducible (see control below) before fixing.

Fix: the alternative pool is now constrained to the *winner's own* fit
bucket when `FIT_MODE=on`: `alternatives=[c for c in ok if ecost(c)==price
and c['arm']!=last and (FIT_MODE != 'on' or fit_bucket(c)==_winner_fit_bucket)]`.
`FIT_MODE=off`/`shadow` has no fit-bucket concept and keeps the prior
cost-only behavior byte-identical.

**Control:** `test-arm-selection-cost-quota-telemetry-01.sh` C1/C2 — C1: two
equal-ecost arms, buckets 0 and 1, seeded `last`=the bucket-0 arm, **no other
bucket-0 alternative exists** → old code would rotate to the bucket-1 arm
(a real, equal-ecost, `!=last` alternative existed); fixed code stays on the
bucket-0 arm. C2 (control): a same-bucket alternative also exists → rotation
still works normally and picks it, never the worse-fit arm.

## 4. §5 — telemetry: `price_ratio` stays, `loser_detail=` is new

`arm_excluded`/`price_ratio` is a catch-all for every arm that survived all
gates and still lost — it cannot distinguish "demoted by fit" from "own
price never measured" from "genuinely lost on a known price," the exact
confusion `arm-selection-logic.md` documents.

**`arm_excluded`/`price_ratio` is left byte-identical** —
`plugins/leadv2/tests/test-exclusion-stages.sh` and
`plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh` both
assert its exact string, and this lane's write set does not include either
file. The distinction rides on a new, purely additive stdout token,
`loser_detail=<arm>:<reason>,...`, computed from the same `ok`/`w` set
`price_ratio` was — never a second decision:

- `insufficient_fit` — `FIT_MODE=on` and the loser's fit bucket is worse
  than the winner's.
- `cost_unknown` — the loser's own `cost_src` ends in `:median` or
  `:unpriced_all` (its price was never measured).
- `higher_expected_cost` — otherwise: a genuinely higher known price.

These three token spellings are taken verbatim from the proposal's §5
vocabulary list; the other listed tokens (`not_in_pool`,
`unsupported_role`, `quota_exhausted`, etc.) already have dedicated,
distinct `_STAGE_ORDER` entries elsewhere and are out of `price_ratio`'s
domain. `loser_detail=` is omitted entirely when there are no losers, and is
not written to `decisions.jsonl` (stdout-only, additive) — the JSON
decision record's `arm_excluded` field is unchanged.

Migration note: older journal lines carrying bare `price_ratio` (no
`loser_detail=`) remain fully readable — `loser_detail=` is a new,
independently-parseable trailing field, never a retrofit of existing
tokens, so historical counts keep their original timestamps and meaning.

**Control:** `test-arm-selection-cost-quota-telemetry-01.sh` D1/D2 — D1:
four arms, one winner, three losers each for a different reason, in ONE
decision line: `loser_detail=costlyfit:insufficient_fit,pricey:higher_expected_cost,unknownprice:cost_unknown`,
with `arm_excluded` still carrying bare `price_ratio` for all three. D2:
single-loser chain confirms `loser_detail` isn't just a copy of
`arm_excluded`'s keys.

## Baseline reconciliation (`test-arm-selection-decision-fixtures-01.sh`)

Ran clean (no concurrent racer — see "sweep hygiene" below), full raw
output in the suite-sweep section. `SUMMARY pass=41 fail=3`. Every
non-baseline byte examined; **exactly two decisions changed**, both
intended:

- **Case 5** (equal ecost, buckets 0/1, seeded `last`=better-fit arm): now
  `PASS: case05: rotation kept the better fit (alpha)` — previously this
  fixture recorded the OLD code's un-constrained rotation. This is the §4.4
  fix landing.
- **Case 10**, two sub-flips, both from the §4.3 fix:
  - `scoped-free-general-out`: was a documented `BASELINE FINDING` (fable
    admitted despite general weekly 97%); now
    `PASS: case10 scoped-free+general-out: fable refused on the general
    window`.
  - `scoped-stale`: the suite's stale-reading check
    (`FAIL: case10 stale: fabricated urgency from an expired reading`) now
    fires, because `reset_urgency` legitimately includes
    `claude:1.257[seven_day],claude/fable:1.257[seven_day]` in this
    invocation. Verified via `--record`: the `[seven_day]` tag proves the
    urgency figure is sourced from the account's genuinely-valid seven_day
    window (pct=10, `hours_to_reset=120.0`), not the deliberately-stale
    scoped reading (`hours_to_reset=0`) — that stale window still
    contributes nothing to urgency, unchanged. Before this fix, `seven_day`
    was popped for Fable entirely, so this legitimate signal was invisible.
    **This is the correct, intended behavior the fix was meant to restore**
    ("weekly preservation: judge each account's remaining allowance against
    its actual reset horizon" — mission §4.3) — the suite's grep-based check
    was written against the old (popped) semantics and needs re-anchoring by
    whoever owns `ARM-SELECTION-DECISION-FIXTURES-01`'s baseline
    (outside this lane's write set); flagging as a named follow-up, not
    silencing it.

All other cases (1,2,3,4,6,7,8,9,11,12,13) are decision-identical to
baseline — checked byte-for-byte with `--record`/diff; the only per-line
differences anywhere in those recordings are (a) `arb_rev` (a content hash
of the arbiter file — necessarily different once the file is edited at
all) and (b) the new additive `loser_detail=` token where applicable.
Neither is a decision change.

The negative control's two remaining `FAIL`s
(`fresh recordings DIFFER from committed baseline`,
`reverting the mutation did NOT restore the baseline`) are the same two
structural facts (`arb_rev` + `loser_detail=`) surfacing through the
suite's own byte-exact restore check — an unavoidable consequence of
landing *any* change to this file, not evidence of drift beyond what's
already explained above.

## Guarding-suite sweep

Ran every suite whose name mentions arbiter, routing, quota, headroom,
reset-urgency or balancer, one clean run with no other process touching the
same log directory (see hygiene note below).

```
nc-arbiter-observed-cost.sh rc=0
nc-quota-reset-unknown-window-name.sh rc=0
nc-quota-reset-unreadable-reset-zero.sh rc=0
nc-quota-reset-wait-predicate.sh rc=0
nc-quota-telemetry-can-price-an-arm.sh rc=0
nc-think-model-arbiter-wins.sh rc=0
test-arbiter-decision-record-inputs.sh rc=0  (pass=6 fail=0)
test-arbiter-seam-plugin-kind.sh rc=1  (PRE-EXISTING RED — named in mission)
test-arbiter-uses-observed-cost.sh rc=1  (PRE-EXISTING RED — named in mission; pass=11 fail=1)
test-balancer-every-arm.sh rc=1  (PRE-EXISTING — pass=17 fail=5, unchanged pre/post this lane's edit)
test-balancer-ranks-by-usable-now.sh rc=0  (18/0)
test-codex-quota-gate.sh rc=0  (10/0)
test-codex-quota-guardrails.sh rc=1  (PRE-EXISTING — pass=28 fail=1, unchanged pre/post)
test-complexity-routing.sh rc=1  (PRE-EXISTING — pass=7 fail=5, unchanged pre/post)
test-effort-routing.sh rc=8  (PRE-EXISTING — environmental: backlog_row_not_found premise-probe refusal, unrelated to this lane)
test-headroom-continuous.sh rc=0  (12/0)
test-headroom-period-invariant.sh rc=0  (6/0)
test-leadv2-review-routing.sh rc=0  (3/0)
test-leadv2-routing-config.sh rc=0  (23/0)
test-provider-quota-gate.sh rc=0  (30/0)
test-quota-daemon.sh rc=1  (PRE-EXISTING — unchanged pre/post; T5 registry-key polling, unrelated)
test-quota-glm-filter.sh rc=0  (8/0)
test-quota-identity-report.sh rc=0  (9/0)
test-quota-lockout-postspawn.sh rc=124  (PRE-EXISTING — environmental timeout/backlog_row_not_found, unrelated)
test-quota-model-tier-granularity.sh rc=0
test-quota-read-anthropic-liveness.sh rc=0
test-quota-read-codex-refresh-race.sh rc=0
test-quota-reset-arbiter.sh rc=1  (PRE-EXISTING RED — named in mission; pass=7 fail=2)
test-quota-standdown-duration.sh rc=0  (16/0)
test-quota-telemetry-can-price-an-arm.sh rc=0  (17/0)
test-quota-unknown-surfaces.sh rc=0  (15/0)
test-quota-weekly-live.sh rc=0  (8/0)
test-quota-weekly-total.sh rc=0  (13/0)
test-reset-urgency.sh rc=0  (12/0)
test-route-arbiter-failure-memory.sh rc=0  (14/0)
test-route-arbiter-loud-refusal.sh rc=0  (4/0)
test-route-arbiter-spend-forecast.sh rc=1  (PRE-EXISTING — pass=7 fail=2, unchanged pre/post)
test-route-arbiter-symlink-install.sh rc=0  (3/0)
test-route-arbiter.sh rc=1  (PRE-EXISTING — pass=24 fail=8, unchanged pre/post)
test-routing-canonical-protected-glm.sh rc=0  (1/0)
test-routing-enforcement-p1.sh rc=124  (PRE-EXISTING — environmental timeout/backlog_row_not_found, unrelated)
test-spawn-arbiter-gate.sh rc=1  (PRE-EXISTING — pass=27 fail=1, unchanged pre/post)
test-think-model-arbiter-wins.sh rc=0  (10/0)
test-think-through-arbiter.sh rc=1  (PRE-EXISTING — 14 pass/1 fail, unchanged pre/post)
test-exclusion-stages.sh rc=1  (PRE-EXISTING — verified below)
test-arm-selection-decision-fixtures-01.sh rc=1  (pass=41 fail=3 — see reconciliation above)
test-fable-is-priced-from-its-own-window.sh rc=1  (pass=9 fail=1 — EXPECTED, see below)
```

### `test-exclusion-stages.sh` — verified pre-existing, not caused by this lane

Failure: `M2 anchors: stages found 1, order found 0 (expected 1 each)`. That
check greps the arbiter source for a literal
`_STAGE_ORDER=['not_in_pool','not_launchable','untrusted','capped','failure_memory','price_ratio']`
anchor string. The live (and pre-this-lane) `_STAGE_ORDER` is
`['not_in_pool','not_launchable','untrusted','caller_constraint','capped','forecast','failure_memory','price_ratio']`
— it already carries `caller_constraint`/`forecast` entries this lane never
touched. Verified directly: swapped the live arbiter file for
`git show HEAD:...leadv2-route-arbiter.sh` (the committed, pre-this-lane
state), re-ran the suite — identical failure, identical message, then
restored the edited file from a backup copy (confirmed byte-identical to
the pre-swap working tree via diff). This suite's anchor string is stale
against an earlier, unrelated lane's `_STAGE_ORDER` additions and was
already red on main before this lane started.

### Other suites confirmed unaffected by this lane (swap-tested)

`test-route-arbiter.sh`, `test-complexity-routing.sh`,
`test-balancer-every-arm.sh`, `test-spawn-arbiter-gate.sh`,
`test-think-through-arbiter.sh`, `test-route-arbiter-spend-forecast.sh`,
`test-quota-daemon.sh`, `test-codex-quota-guardrails.sh` — each re-run
against the pristine pre-this-lane arbiter file; pass/fail counts identical
to the post-edit sweep in every case. None of these suites' failures are
caused by this lane's four changes.

### `test-fable-is-priced-from-its-own-window.sh` — 1 EXPECTED new red (C1)

This is the 0485 lane's own suite, asserting the OLD replace-semantics this
lane's §4.3 fix deliberately overturns (per the async-question resolution
above). `C1` fixture: general weekly=96 (over the claude ceiling) with the
arm's own scoped window healthy (2%) — the suite asserts fable is **not**
excluded in this shape (`,fable:capped,` must be absent). Under the fix,
the general weekly window now correctly also binds, so fable IS excluded
(`arm_excluded=fable:capped,sonnet:capped`) — the direct, intended
consequence of keeping both windows. `C2`/`C3`/`C4` remain green: none of
them exercise "general aggregate over ceiling, scoped healthy" in a way
that depended on replace-semantics (C2: scoped exhausted → capped either
way; C3: shared session window dominates → capped either way; C4: a
non-scoped arm, unaffected by this fix at all). `C1` needs a rewrite by
whoever owns this suite next (outside this lane's write set — the mission
explicitly assigns only `leadv2-route-arbiter.sh` to this lane) to assert
the corrected semantics; flagging as a named follow-up.

### Sweep hygiene note

An early sweep attempt ran two copies of the same suite-runner script
concurrently against one shared log directory; their writes interleaved and
one suite's logged tail briefly read `fail=1` where the file itself, read
moments later, held `fail=0` — a pure race, not a real regression (caught
and discarded before drawing any conclusion from it). All results in this
report come from a single, exclusive run per suite (or a swap-and-restore
pair for the pre-existing-red verifications above), never from a
concurrent/racing invocation.

## Static checks

`bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — OK.
`bash -n plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh`
— OK. The embedded Python heredoc (`python3 - "$routing" <<'PY' ... PY`,
~2346 lines) compiles cleanly via `compile(..., "exec")`. This lane's own
new suite: `SUMMARY pass=14 fail=0`.

## Explicitly out of scope, confirmed untouched

`plugins/leadv2/config/leadv2-routing.yaml` (sibling lane), capability
bands/pool membership/opus identity/recon eligibility/review pools, any
bandit/training/auto-policy-learning loop, review counters, caps, flash
permissions. `_observed_rounds` logic and NNLS/provider-drain inference were
read but not modified.

## ROUND 2 (2026-09-16) — the code stands; two artefacts catch up with it

Round 1's arbiter code is untouched this round: `git diff fc36ecad HEAD --
plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` is empty. What moved is
the two artefacts the round-2 brief names, plus three pin re-anchors inside
the fixtures suite (declared in §5 below).

### 1. The Fable suite now asserts the founder ruling

`plugins/leadv2/scripts/tests/test-fable-is-priced-from-its-own-window.sh`
keeps its PATH (CI suite-selection keys on it) and opens with a header
saying the name is HISTORICAL: decision 0485 (2026-09-13) built the
model-scoped weekly window end to end and let the scoped window REPLACE the
account weekly for the scoped arm; the founder ruling of 2026-09-16 (this
lane, round 2) keeps BOTH windows — the worst readable window binds.

- **C1 flipped to the ruled direction**: weekly_all=96, scoped=2, session=7
  → `util_claude_fable=96` (the worst of its three readable windows), fable
  AND sonnet capped, codex wins. The old C1 asserted the opposite (scoped
  alone frees fable) and was the round-1 red the lead's table recorded.
- **C2 kept unchanged — it IS the required mirror** (scoped exhausted=100,
  aggregate=30 healthy → fable capped, sonnet wins); its comment now names
  it the ruled mirror so the next reader knows the pair is deliberate.
- **C5a/C5b are new**: the same rule pinned at PRICING level, under every
  ceiling so cap logic cannot mask the number — aggregate 60 vs scoped 30
  reads `util_claude_fable=60` (a replace-shaped regression reads 30);
  aggregate 30 vs scoped 60 also reads 60.
- P1/P2 (publisher) and R-live/R1/R2/R3 (resolver) halves are unchanged —
  see follow-up §6.

Post-rewrite: `SUMMARY: pass=12 fail=0`, rc=0.

### 2. Baseline re-frozen — every changed field, enumerated

Regenerated from the post-change tree with
`test-arm-selection-decision-fixtures-01.sh --record .../baseline/`, then
acceptance mode proves twice-run determinism, byte-identity to the committed
baseline, and the negative control (mutation moves the winner
glm→codex, revert restores byte-for-byte). Field-level enumeration of the
re-freeze diff (old → new, all 13 recordings, 20 invocations):

| where | field | old → new | why |
|---|---|---|---|
| all 13 files, all invocations | `arb_rev` | `a488efe537bf` → `1e4bd06dee6c` | content hash of the arbiter file; round 1 edited it, so this necessarily moved. Not a decision. |
| 10 of 20 invocations (01, 02, 03, 04×2, 05, 06×2, 07, 08-complex, 10-scoped-out, 10-scoped-stale, 11) | `loser_detail` | absent → e.g. `codex:cost_unknown,glm-flash:insufficient_fit,sonnet:cost_unknown` | §5 telemetry: the additive loser-reason token. `arm_excluded`/`price_ratio` stays byte-identical beside it. Not a decision. |
| case05 | winner | `arm=beta model=glm-5.3-flash chain=beta,alpha` → `arm=alpha model=glm-5.3 chain=alpha,beta` | **intended §4.4**: the baseline had frozen the OLD un-constrained rotation (equal ecost, seeded `last`=alpha, jumped to worse-fit beta). Round 1 constrains rotation to the winner's fit bucket, so alpha keeps winning. Loser relabelled `alpha:price_ratio` → `beta:price_ratio` + `loser_detail=beta:insufficient_fit`. |
| case10 scoped-free+general-out | decision | `rc=0 arm=fable reason=cheapest_capable` → `rc=3 arm=refuse reason=all_arms_capped`; `util_claude_Fable` 10 → 97; `arm_excluded sonnet:capped` → `fable:capped,sonnet:capped` | **intended §4.3 / founder ruling 2026-09-16**: the exhausted account weekly now binds fable though its scoped window reads 0. The fixture's only review arms are fable and sonnet (both claude), so the task refuses instead of re-routing. |
| case10 scoped-stale | `reset_urgency` | `claude:1.257[seven_day]` → adds `claude/fable:1.257[seven_day]` | keep-both makes the LIVE aggregate legible to the scoped arm's urgency pricing; the expired scoped window still contributes nothing. Winner unchanged. |
| case10 scoped-stale | candidate `effective_cost` (claude) | 1.6667 → 1.3258 | the added `[seven_day]` urgency weight re-prices claude's ecost — ranking-only, bounded [1,2], exclusion cliffs untouched. Winner unchanged (sonnet). |
| case09, case12, case13 | — | `arb_rev` only | decision-identical |

That is the complete list. Beyond `arb_rev`, `loser_detail`, and the three
case05/case10 entries above, not one byte moved in the other eleven
scenarios — the round-1 verification ("not one routing decision moved" on
cases 1-4, 6-9, 11-13) survives re-freezing verbatim.

### 3. Paired table vs main (real exit codes, 2026-09-16)

| suite | main | branch pre-round-2 | branch post-round-2 |
|---|---|---|---|
| `test-arm-selection-decision-fixtures-01.sh` | rc=0 (pass=44 fail=0) | rc=1 (pass=41 fail=3) | **rc=0 (pass=44 fail=0)** — baseline re-frozen, changes enumerated in §2 |
| `test-fable-is-priced-from-its-own-window.sh` | rc=0 (pass=10 fail=0) | rc=1 (pass=9 fail=1) | **rc=0 (pass=12 fail=0)** — rewritten to the ruling |
| `test-arbiter-reads-capability-floor.sh` (`tests/`) | rc=1 (5 passed, 1 failed) | rc=1 (5 passed, 1 failed) | rc=1 (5 passed, 1 failed) — still red in BOTH columns, as required; this lane touched nothing it reads |

Raw evidence: main-column runs executed from
`/Users/kostiantyn.vlasenko/Projects/leadv2` (main checkout, only
runtime-state dirt); branch-column runs from this worktree.

### 4. Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/tests/test-fable-is-priced-from-its-own-window.sh && echo BASH_N_OK
BASH_N_OK
$ bash -n plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh && echo BASH_N_OK
BASH_N_OK
```

No Python file was changed this round, so `python3 -m py_compile` has no new
target (round 1 compiled the embedded heredoc; nothing moved since).

`bash tests/run-all.sh --scope changed` — rc=1, reconciled suite-by-suite in
§7: every blocking failure is pre-existing on main or tree-independent; both
of this lane's suites passed inside the same run.

### 5. Write-set deviation, declared: three pins in the fixtures suite

The round-2 write set names the baseline DIRECTORY but not
`test-arm-selection-decision-fixtures-01.sh`. Three pin re-anchors were made
in it anyway, because the re-freeze mandate is otherwise unreachable or
hollow:

1. **case10 stale check (required for green)**: the old grep treated ANY
   `claude/fable` urgency in the stale block as fabricated. Under keep-both,
   `claude/fable:1.257[seven_day]` is legitimate (live aggregate), so the
   check re-anchors to: no urgency sourced `[weekly_scoped...]` (the expired
   window), and the aggregate-sourced token present. Leaving it un-edited
   kept the suite red against the re-frozen baseline for a false reason.
2. **case10 scoped-free+general-out either/or → hard pin**: both branches
   used to `pass`. Now admission is a FAIL (replace-shaped regression,
   founder ruling 2026-09-16) and refusal is the rule.
3. **case05 either/or → hard pin**: `BASELINE FINDING` acceptance of the
   worse-fit rotation became a FAIL (§4.4 regression).

No recording mechanics, fixtures, or normalization were touched — the
re-frozen bytes are pure arbiter output. Byte-identity (acceptance check 4)
remains the real guard; the pins now name regressions instead of shrugging
at them.

### 6. Follow-up (named, not silenced): the resolver half still substitutes

`leadv2-glm-policy-resolve.py` (`live_anthropic_pct`) still prices fable by
max(session, scoped) — 0485's substitution — so its review-pool path
(R-live/R1/R2/R3, unchanged and green in the rewritten suite) admits fable
while the account aggregate is exhausted. That file is outside this lane's
write set and outside the ruling's patch (the ruling concerned the arbiter's
window set); the suite header names the split. The owner of
`leadv2-glm-policy-resolve.py` should decide whether the ruling extends
there.

### 7. Run-all changed-scope (2026-09-16, this lane's final tree)

```
run-all: 25 passed, 22 failed, 0 known-red (allow-listed, non-blocking),
1 known-red-skipped (budget mode, still run by --scope all),
0 gone-green (remove from allow-list), scope=changed      rc=1
```

Inside the SAME run, all three of this lane's suites PASSED:
`test-arm-selection-decision-fixtures-01.sh` (re-frozen baseline),
`test-fable-is-priced-from-its-own-window.sh` (rewritten), and round-1's
`test-arm-selection-cost-quota-telemetry-01.sh` (14/0).

All 22 blocking failures are inherited, each verified one of two ways:

- **Pair-measured today, branch vs main checkout, rc identical in every
  case** (the changed-scope selection ran them because round 1's arbiter
  diff is in this lane's range — none of them reads this round's files):

  ```
  test-arm-pool-reachability.sh        branch=1 main=1 SAME
  test-arm-admission.sh                branch=1 main=1 SAME
  test-arm-capability-honoured.sh      branch=1 main=1 SAME
  test-freepool-capability-floor.sh    branch=1 main=1 SAME
  test-freepool-gets-work.sh           branch=1 main=1 SAME
  test-glm-flash-arm.sh                branch=1 main=1 SAME
  test-launch-uses-the-chosen-arm.sh   branch=2 main=2 SAME
  test-router-v2-capability-fit.sh     branch=2 main=2 SAME
  test-router-v2-shadow-mode.sh        branch=1 main=1 SAME
  tests/test-arbiter-reads-capability-floor.sh branch=1 main=1 SAME  (§3)
  ```

- **Documented pre-existing in round 1's sweep** (swap-tested there against
  the pristine pre-lane arbiter, pass/fail counts identical pre/post):
  `test-arbiter-seam-plugin-kind.sh`, `test-arbiter-uses-observed-cost.sh`,
  `test-quota-reset-arbiter.sh` (the three the mission named),
  `test-complexity-routing.sh`, `test-effort-routing.sh` (environmental),
  `test-exclusion-stages.sh` (stale anchor string),
  `test-route-arbiter-spend-forecast.sh`, `test-route-arbiter.sh`,
  `test-spawn-arbiter-gate.sh`, `test-think-through-arbiter.sh`,
  `test-t13-slice2.sh` (baseline changed-scope red, measured 2026-09-01),
  and the `run-core-offline.sh` aggregate whose children are the same set.

Additionally verified tree-independent today (passed standalone on BOTH
trees after flaking inside the runner): `test-unmetered-account-not-
penalised.sh`, `test-think-model-arbiter-wins.sh`, and the
`test-status-surface-*` trio — none appears in the blocking list.

### 8. Mutation controls (leadv2-mutation-control.sh artifacts)

Two worker-mode controls re-introduce the exact 0485 replace-shape —
`windows.pop('seven_day', None)` appended back at the scoped-window site —
into a scratch copy, one per suite, and prove each suite goes red because of
it. Artifacts under `docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/
mutation-control/` (committed; gitignore force-add). Run after the code
commit (8b271082) so lane_diff_hash binds the committed HEAD.

```
MUTATION-CONTROL ok suite=test-arm-selection-decision-fixtures-01.sh
  red_line=FAIL: case10 scoped-free+general-out: fable admitted while the
  general weekly is 97% (replace-shaped regression — founder ruling
  2026-09-16 keeps both windows)
  artifact=mutation-control/20260916T185104Z-15292.txt

MUTATION-CONTROL ok suite=test-fable-is-priced-from-its-own-window.sh
  red_line=FAIL: C1 arbiter output=... util_claude_fable=7 ...
  arm_excluded=fable:price_ratio ...   (the pop makes fable read 7 and be
  ADMITTED as a candidate — the replace shape, caught by C1)
  artifact=mutation-control/20260916T185124Z-24248.txt

diff_hash=8eb22cb7ccf1... (both runs: identical mutant, identical hash)
lane_diff_hash=2c459d9d7114... (both runs: the committed lane diff)
```
