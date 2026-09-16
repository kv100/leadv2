# ARM-SELECTION-COST-QUOTA-TELEMETRY-01 — §4.2, §4.3, §4.4 and §5-telemetry, arbiter only

Founder order 2026-09-16: apply `docs/reference/arm-selection-proposal-2026-09-16.md` immediately.
This lane owns everything in that proposal that lives in
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`. A sibling lane owns the config; do not touch
it. Read the whole proposal first, plus `docs/reference/arm-selection-logic.md` §3 and §5.

## Four changes, four separate claims, four separate controls

### 1. §4.2 — cost provenance. Unknown must stay visibly unknown.

Today `router_v2.cost` gives real numbers only to the GLM family; `codex`, `anthropic` and others are
`null` and fall back to the **matrix median, 1.0**. The effect is that haiku, sonnet, opus, fable,
luna, terra, astra and sol are all priced identically, so `cheapest_capable` cannot separate any of
them.

- Key cost by provider **and actual model and effort and plan/account scope** — not provider alone.
- Preserve `source`, `observed_at`, `sample_count`, `confidence` and an explicit unknown status.
- **Do not replace `null` with an invented 1.0 and call it measured.** If the algorithm needs a
  numeric fallback, label it a fallback policy and keep "unknown price" distinguishable from "price
  equal to 1.0". The existing `cost_src` diagnostic already exposes the median fallback — preserve
  it.
- **Do not re-fit the NNLS/provider-drain inference.** The yaml records that this was tried, gave a
  negative R-squared, and was ruled out by the founder because the shared quota meters are
  collinear. Re-running it on the same data is forbidden. Retain provider-level unknowns until there
  are identifiable observations or a published plan contract.
- Z.ai's Team Plan publishes roughly one-third credit weight for Flash. Apply that **only after
  verifying this account is on that billing contract**, preserve cache/input/output and
  peak/off-peak distinctions, and never copy API price ratios into Max/Team/Codex weekly percentages.
- `_observed_rounds` **already** multiplies ecost from class/arm history and `OBS_ON` defaults on.
  **Do not add a second rounds multiplier.** Verify event coverage, sample selection and the
  effective flags instead. Include failed, cancelled and timed-out attempts; keep
  infrastructure-failure attribution; avoid survivor bias. No new automatic weight-learning loop —
  the founder ruled that out.

**Control:** a fixture where a genuinely unknown price and a genuinely-1.0 price must produce
*distinguishable* decisions or at minimum distinguishable recorded provenance. If they are
indistinguishable, the change did not land.

### 2. §4.3 — quotas, and a real suspected defect at `:790`

`leadv2-route-arbiter.sh:790` does `windows.pop('seven_day', None)` in the scoped-Claude branch:
scoped weekly **replaces** general weekly. The founder states Fable consumes **both** meters
simultaneously. If that is right, this silently drops a binding constraint.

- Keep both constraints. Never sum them, never let one replace the other.
- Add a case that fails on today's code: general weekly exhausted while scoped weekly is available
  (and the reverse). Both must refuse.
- Scoped exhaustion must not block an unrelated sonnet route.
- Expired or stale readings are **not** headroom — they stay unknown, and unknown is never zero.
- Weekly preservation: judge each account's remaining allowance against its actual reset horizon;
  the 5h window controls immediate admission only. **A near 5h reset must not overwhelm a depleted
  weekly allowance.** Budget prediction is not an invented hard cap.

**This is stated in the proposal as a source-level finding, not a proven live defect** — verify it
before fixing it, and if the semantics turn out to be correct as written, say so plainly and leave
the code alone. A fix for a defect that does not exist is worse than no fix.

### 3. §4.4 — rotation must not buy variety with fitness

`:2096`: `alternatives = [c for c in ok if ecost(c) == price and c['arm'] != last]`, then the first
alternative wins. Equal `ecost` does **not** imply equal fit bucket. Check whether this can rotate
to a *worse* fit bucket purely to avoid repeating the last arm.

**The proposal is explicit that this is a verification item, not a reproduced incident.** Measure
first. If it can happen, constrain rotation to preserve fit bucket, eligibility and quota
constraints. If it cannot, show why and change nothing.

### 4. §5 — telemetry vocabulary

`price_ratio` is currently a catch-all pinned on every arm that survived all gates and lost. It
cannot distinguish "barred" from "ranked second", which is exactly the confusion that put two false
claims into `arm-selection-logic.md`. Replace it with distinct reasons:

```
not_in_pool · unsupported_role · insufficient_fit · quota_exhausted ·
weekly_pacing_preference · cost_unknown · higher_expected_cost ·
latency_preference · infrastructure_unavailable · explicit_override
```

Keep a migration note so older journal lines carrying `price_ratio` remain readable — historical
counts must retain their timestamps rather than being retro-relabelled.

## Acceptance — against the frozen baseline

Lane `ARM-SELECTION-DECISION-FIXTURES-01` freezes the pre-change decisions and provides
`plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh`. Reconcile against it: for
every fixture, either the decision is unchanged, or the change is intended and the report says which
case and why. **A changed decision you cannot explain is a defect, not a side effect.**

From the proposal's §6, the cases this lane owns: 5 (equal ecost, different fit buckets — rotation
cannot pick worse fit), 6 (null price stays visibly unknown; known-cheap is not confused with median
fallback), 7 (observed-rounds adjustment happens exactly once; missing samples and infrastructure
errors do not invent success rates), 8 (same provider, different models/efforts are distinguishable
and the model choice survives launcher resolution), 10 (Fable scoped-positive/general-zero and the
reverse both refuse; scoped exhaustion does not block unrelated sonnet; expired readings are not
fabricated headroom), 11 (near 5h reset with scarce weekly versus another suitable account — weekly
preservation still matters), 12 (same-account/profile UUID mismatch produces no mislabeled quota or
launch; project defaults do not override an explicitly chosen dispatcher account), 13 (direct and
fallback dispatch run the same final admissibility checks and keep actual identity and effort).

All hermetic. **No live provider spend in acceptance.**

## Explicitly NOT in scope

- `plugins/leadv2/config/leadv2-routing.yaml` — the sibling lane owns it.
- Capability bands, pool membership, opus model identity, recon eligibility, review pools.
- Any bandit, training loop or automatic policy learning.
- Resetting review counters, disabling caps, or rolling back founder-approved flash permissions.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh
docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md
```

## Before you finish

This file is guarded by many suites. Run every one whose name mentions arbiter, routing, quota,
headroom, reset-urgency or balancer, and report each by name with its exit code. Three of them
(`test-arbiter-seam-plugin-kind`, `test-arbiter-uses-observed-cost`, `test-quota-reset-arbiter`) were
already red on main as of 2026-09-16 — show them red before your change too, so an inherited failure
is never reported as yours and yours is never hidden behind theirs.

## ROUND 2 (lead, 2026-09-16) — the change stands; two artefacts must catch up with it

Round 1 landed the four changes and the lead verified them against the frozen baseline. The result
was better than the terminal suggests. The lane died `terminal=dead cause=e2e_regression`, and that
verdict is **partly false and partly true** — it was resolved suite by suite, paired against main:

| suite | main | branch | verdict |
|---|---|---|---|
| `test-arm-selection-decision-fixtures-01.sh` | rc=0 | rc=1 | INTENDED — the baseline predates this change |
| `test-fable-is-priced-from-its-own-window.sh` | rc=0 | rc=1 | REAL, and now resolved by a founder ruling |
| `test-arbiter-reads-capability-floor.sh` | rc=1 | rc=1 | pre-existing, not this lane |

What the baseline proved about round 1, and it is the important part: **not one routing decision
moved.** Across all thirteen frozen scenarios the winning arm, every fit bucket, every effective
cost to sixteen decimals and every exclusion are identical to main. The only differences are
`arb_rev` (the file changed, so of course it did) and one added field:
`loser_detail=glm-flash:higher_expected_cost,sonnet:cost_unknown` — which is precisely the §5
telemetry vocabulary, doing exactly what it was asked to do. The legacy `price_ratio` contract is
preserved byte-identical alongside it, so no historical reader breaks. The lane's own suite is 14/0.

So round 1's code is sound. Two artefacts around it now disagree with it, and that is all.

### 1. The Fable window conflict — RULED ON BY THE FOUNDER, 2026-09-16

Round 1 implemented correction 5: `windows.pop('seven_day', None)` is gone, so the account weekly
aggregate stays in `windows` beside `weekly_scoped` and `five_hour`, and the existing
worst-of-readable-windows rule prices the arm — never a sum, never a replace.

`test-fable-is-priced-from-its-own-window.sh` encodes the OPPOSITE, from decision 0485: Fable is
priced from its own scoped window and the account aggregate does not bind it. That suite was green
on main, so this is not a bug — it is two deliberate decisions in direct contradiction. The lead put
it to the founder with both consequences stated rather than picking one.

**Founder's ruling: keep BOTH windows; rewrite the suite.** The consequence he accepted explicitly:
when the account weekly is exhausted (it reads 96% used right now) Fable is `capped` and takes no
work, even when its own scoped window is free.

Therefore:

- **Do not revert the `seven_day` change.** It is now the intended behaviour.
- **Rewrite `test-fable-is-priced-from-its-own-window.sh`** so it asserts the new rule: both windows
  are readable, the worst one binds, and an exhausted account weekly caps Fable even with scoped
  headroom. Keep the existing file PATH — CI suite-selection maps key on it — and open the file with
  a header saying the name is historical, naming decision 0485, this founder ruling and its date, so
  the next reader is not misled by the filename.
- **Give it the mirror case too**: scoped exhausted while the account weekly is healthy must also
  cap. One direction alone would let a replace-shaped bug back in unnoticed.

### 2. Re-freeze the fixtures baseline, with reasons

`ARM-SELECTION-DECISION-FIXTURES-01` deliberately froze the PRE-change decisions, so it is supposed
to go red exactly once, here, and then be re-frozen. Do that:

- Regenerate the baseline under `docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline/` from the
  post-change tree (`git add -f` — `.gitignore` carries `docs/handoff/*/*` with an exception only
  for `*.md`).
- In `report.md`, list **every field that changed and why**, per the proposal's §7: "first freeze
  baseline decisions, then show changed outcomes with reasons." Today that list is exactly two
  entries, `arb_rev` and `loser_detail`, plus whatever the Fable rewrite moves. If it grows beyond
  that, each new entry needs its own justification — an unexplained changed decision is a defect,
  not a side effect.
- The negative control must still work after re-freezing: mutate, see the decision move, revert, see
  the baseline restored byte-for-byte.

### Write set — unchanged from round 1, plus the two artefacts

```
plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
plugins/leadv2/scripts/tests/test-arm-selection-cost-quota-telemetry-01.sh
plugins/leadv2/scripts/tests/test-fable-is-priced-from-its-own-window.sh
docs/handoff/ARM-SELECTION-COST-QUOTA-TELEMETRY-01/report.md
docs/handoff/ARM-SELECTION-DECISION-FIXTURES-01/baseline/
```

### Before you finish

Re-run the three suites from the table above, paired against main, and put the table in the report
with real exit codes. `test-arbiter-reads-capability-floor.sh` must still be red in BOTH columns — if
it goes green on your branch, say so, because that would mean you changed something nobody asked you
to change.
