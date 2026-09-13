# Price the arm per PROVIDER, not per model

Founder decision, 2026-09-13, taken on a measurement rather than a preference.

## Why per-model pricing is off the table

`leadv2-drain-weights.py` (non-negative least squares of Δquota-pct on per-model
token counts) after the telemetry fix landed 99 intervals on the 5h window and 61
on the 7d window — five times the data of the first attempt. Both fits are still
worse than the mean:

| window | kept intervals | R² |
|---|---|---|
| 5h | 99 | −0.3152 |
| 7d | 61 | −0.7937 |

and the diagnostics name the reason: `max_abs_corr = 1.000`, `degenerate_pairs = 7`.
The per-model token columns are **linearly dependent**, because quota is metered
per PROVIDER. Haiku, Sonnet, Opus and Fable all burn one Anthropic bucket, so the
data contains no information separating them. This is not a data-volume problem
and more data will not fix it.

## The shape the founder chose

```yaml
cost:            # measured, per provider
  glm-flash: 0.33   # Z.AI credit-weight ratio, the one number that was ever derived
  glm:       1.0
  codex:     ?      # derive
  anthropic: ?      # derive — one bucket over haiku/sonnet/opus/fable

capability:      # per model; this is where models differ
  opus:   [plan, audit, safety]
  sonnet: [dev, review]
  haiku:  [discovery]
  fable:  [plan, audit, review]
```

Six authored numbers (`haiku 2, codex 3/4/7, sonnet 5, fable 8, opus 9`) come out.
**Nothing invented goes in to replace them.**

## How to derive the two unknowns — and the honest failure mode

Within a single provider there is exactly one token column against one window, so
the collinearity that killed the per-model fit does not exist. The quantity to
derive is **fraction of that provider's own window consumed per million tokens**:

```
cost_provider = Δpct_provider_window / Mtok_spent_on_that_provider
```

Fit it per provider, separately, on intervals where that provider's window moved.
Report R² for each. Requirements:

- **If a provider's fit is also bad, say so and leave its price unset.** A second
  honest negative beats a fitted number nobody can defend. The founder has
  already accepted one negative result today; he will accept another.
- Costs live in different currencies — a percent of the GLM window is not a
  percent of the Anthropic window. State explicitly how you make them
  comparable, or state that you cannot and what the arbiter should do instead.
  Do not silently normalise.
- **Fable carries TWO limits**, not one: the shared `weekly_all` AND a
  `weekly_scoped` limit scoped to Fable, in addition to, not instead of. Whatever
  you build must charge Fable for both. This is the one place where a per-model
  term survives, and it is a LIMIT term, not a price.
- Quota is REMAINING, not consumed: `~/.claude/burn/quota-fragment.sh` reads
  `pct = d.get("remaining_pct")`. Getting this backwards inverts every decision.

## The arbiter side

`ecost(c) = (cost / headroom_weight) * observed_rounds + floor + unknown_probe_penalty + complexity_penalty`
at `lib/leadv2-route-arbiter.sh:1806`, with
`_HEADROOM_W_MIN=0.2, _HEADROOM_W_MAX=1.0, _HEADROOM_U_SAT=8.0` — so headroom can
move effective price by at most 5×.

Re-derive that ceiling against the new provider prices. With per-model costs gone,
the price spread narrows, and a 5× headroom ceiling may now be the right size or
may now dominate. Measure it; do not keep the constant because it is there.

Also note what the founder asked for beyond price, and say which of these the new
shape supports and which it does not: weekly AND 5h windows (Codex has no 5h),
model capability, task type, task complexity, an estimate of how many tokens the
task will eat, and a preference for a provider whose window resets soon.

## Acceptance

- `leadv2-drain-weights.py` extended to the per-provider fit; both R² reported,
  and any provider left unpriced named with its R².
- The capability matrix in `~/Projects/leadv2/plugins/leadv2/config/leadv2-routing.yaml`
  restructured to the shape above. Every remaining number carries a comment
  naming the run that produced it. A number without a source does not ship.
- A suite proving the arbiter reads provider cost, and a negative control:
  flip one provider's cost in a scratch copy and show the chosen arm changes.
- A replay: take the 130 routing decisions already in the journals and show what
  the new pricing would have chosen, versus what was chosen. Report the
  disagreement count. This is the measurement that tells us whether the change
  does anything at all.
- Second-model review, named. `run-all.sh --scope changed` proof after commit.
- Commit inside `~/Projects/leadv2`.

## Do not

- Do not dispatch this before the telemetry lane (`ac8a48dc2939`) is terminal —
  it holds `leadv2-dispatch-code.sh` and `leadv2-dispatch-product-close.sh` in its
  write set and the dispatcher will refuse on overlap.
- Do not invent a price. That is the entire point of this line.
