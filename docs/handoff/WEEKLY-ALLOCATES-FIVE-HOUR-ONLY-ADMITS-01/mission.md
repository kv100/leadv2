# WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01

Founder order 2026-09-16. Standing rules: `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` —
read them first.

## The order, and what it is NOT

> "суть же не в том чтобы считать сжигание а именно распределять работу по недельной квоте,
>  с учётом 5 часовой. Никто никогда не будет знать сколько задач и каких будет на этой неделе"

Two halves, and the second one kills a whole class of design:

1. **The weekly window is the allocation key.** It decides who gets a task, so the week's capacity
   is spread instead of concentrated and nothing is exhausted early.
2. **The five-hour window is an admission constraint, not a preference.** It answers "can this arm
   take work right now", never "who deserves this task".
3. **No demand forecast anywhere.** Nobody knows how many tasks of what kind the week holds. Every
   decision is made online, from current state only. A spend schedule, a burn curve, a per-day
   budget, a "by day 3 we may have used X%" target — all of these need a forecast and are therefore
   **out of scope**. If your design needs to know future demand, it is the wrong design.

An earlier framing of this row as a 7-day spend budget was wrong and the founder corrected it. Do
not reintroduce it.

## The defect, measured on the live arbiter

`reset_urgency_weight` (`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`, the function and the
`ARBITER-DECISION-INPUTS-01 D1` comment above it) scores `waste = remaining × (1 − hours_to_reset /
period)` over **every readable window** and takes the **maximum**. So a five-hour bucket that is
about to reset produces a large preference multiplier. It enters `ecost()` as a denominator term
(`_base = provider_cost(c) / (_w * _ru)`), alongside `headroom_weight`, which for a ≥24h window is
the weekly **reserve** (`remaining_fraction`) — the half that is already correct.

Measured hermetically, both arms priced 1.0, observed-cost and spend-forecast off:

```
glm  : weekly 40% used, five_hour fresh
codex: weekly 45% used, five_hour 15% used and 0.2h from reset

headroom_priced = codex:0.64, glm:0.68        <- weekly reserve prefers glm
reset_urgency   = codex:1.816[five_hour], glm:1.243[weekly]
-> arm=codex   (glm excluded: price_ratio)
```

The urgency term's spread here (1.24 → 1.82, a factor of 1.46) is far wider than the headroom term's
(0.64 → 0.68, a factor of 1.06), so the five-hour bucket overrode the weekly allocation key. Note the
label in the evidence line: `[five_hour]` — the arbiter names the window it priced urgency from.

**Boundary.** This is a constructed fixture with chosen numbers. It establishes that the five-hour
term *can and does* override the weekly key when the weekly windows are close. It does **not**
establish that it always does — with a wide weekly gap the earlier variant of this fixture picked
glm correctly. Do not restate this finding more strongly than that.

## Acceptance (red at dispatch, rc=1 measured 2026-09-16)

```
bash docs/handoff/WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01/probe.sh
```

**This file is not in your write set. Do not edit it.** Making it pass by changing the fixture is the
prohibition in `lane-rules.md`, and it is the one thing that would make this row worthless.

## What the fix must establish

1. `reset_urgency_weight` prices urgency from the **weekly** window only. A five-hour window nearing
   reset is not a reason to prefer an arm. Founder order, same day: the near-reset burn rule was
   ordered for the weekly quota, never the five-hour one.
2. The five-hour window keeps a real job: **admission**. An arm whose five-hour bucket cannot take
   the work now must be filtered out or deferred — not merely down-weighted. Say where you put that
   check and why there rather than in the score.
3. `headroom_weight`'s short-window branch (`_headroom_ramp(usable_now)` for periods under
   `_HEADROOM_LONG_PERIOD_HOURS = 24.0`) is the other place a five-hour rate becomes a preference.
   Decide what it should do under the order above and justify it. Note `usable_now`'s own hazard,
   already documented in the comment block above `headroom_weight`: it is remaining-pct **per hour**,
   so it is not comparable between a 5h and a 168h window. That comment is worth reading in full
   before you touch anything — its author already mapped this trap.
4. Do not silently rescale a founder-set constant. If `_HEADROOM_U_SAT`, `_HEADROOM_W_MIN/MAX`,
   `_RESET_URGENCY_W_MIN/MAX` or `_HEADROOM_LONG_PERIOD_HOURS` change meaning, say so explicitly with
   the before/after.

## Three suites encode today's behaviour and will have to change

`test-reset-urgency.sh`, `test-headroom-period-invariant.sh`, `test-headroom-continuous.sh`.
`test-headroom-period-invariant.sh` exists because of `THE-BALANCER-CONCENTRATES-ON-THE-EMPTIEST-
BUCKET-01` (founder, 2026-09-14) — that order made the **weekly** window reserve-based and is NOT
superseded; keep it working. Only the five-hour half moves. Where a case must change, quote the cause
class `test_encodes_superseded_requirement` with the founder order id and date, per `lane-rules.md` —
and re-run all three, reporting `pass=N fail=N` for each before and after.

## Related, separately owned — do not fix here

- Row `7ea4fed65451` (`FIVE-HOUR-WINDOW-NEVER-ENTERS-THE-ACCOUNT-CHOICE-01`) is the same root cause
  in the **account** picker, `lib/leadv2-claude-profile-pick.py`. Different file, different lane.
  Coordinate the concept, not the code.
- `fit_mode=off` in every decision line measured today. `_fit_order` and `fit_pick` are computed as a
  shadow on every call but never sort (`FIT_MODE`, gated by `LEADV2_ARBITER_CAPABILITY_FIT` or the
  config's `enabled`). That is the founder's "у кого какая задача получится лучше" half, built and
  dark. **Report what you observe about it; do not flip it.** Turning it on is a separate decision
  with its own row.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
plugins/leadv2/scripts/tests/test-reset-urgency.sh
plugins/leadv2/scripts/tests/test-headroom-period-invariant.sh
plugins/leadv2/scripts/tests/test-headroom-continuous.sh
docs/handoff/WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01/report.md
```

Cannot be widened after dispatch. `probe.sh` is deliberately absent from this list.

## Report

`docs/handoff/WEEKLY-ALLOCATES-FIVE-HOUR-ONLY-ADMITS-01/report.md`: the before/after decision line
for the fixture above; where admission now happens and why there; what you did about points 3 and 4;
the three suites' counts before and after with every changed case justified by cause class; and one
negative control per independent claim. Every number carries its boundary.
