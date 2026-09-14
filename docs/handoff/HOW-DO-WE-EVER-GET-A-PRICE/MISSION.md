# HOW-DO-WE-EVER-GET-A-PRICE-01

Founder order, 2026-09-14: *«пускай она скажет где же и как же решить нам это всё получить (цену),
мы пойдём до конца чтобы арбитр всё понимал и работал корректно»*.

This is a DIAGNOSIS-then-DESIGN mission, not a "fit it again" mission. Three lanes have now tried
to fit a price from observational data and all three failed with the same signature. Your job is to
say **why**, and then to name and cost the path that actually produces a defensible number.

## What is already measured — do not re-derive any of this

The arbiter's cost term is per PROVIDER (founder ruling 2026-09-13). Current `router_v2.cost`
(`plugins/leadv2/config/leadv2-routing.yaml`): `glm-flash: 0.33`, `glm: 1.0`, `codex: null`,
`anthropic: null`, `freepool: 1.0`. A `null` price falls through to `_COST_MEDIAN` = median of known
prices = **1.0**, so codex, anthropic and glm are priced identically today and only glm-flash
differs. Provenance is emitted as `cost_src=<provider>:measured|median|unpriced_all|legacy_row`.

**glm-flash's 0.33 was never fitted.** It is Z.AI's *published* credit-weight ratio
(`leadv2-routing.yaml:178`, founder ruling q-bba84179, 2026-09-02, citing
`docs.z.ai/devpack/teamplan.md`). That is the only price in the system with a defensible origin.

### Fit attempt 1+2 — `leadv2-drain-weights.py`, merged as `b78bb547` (2026-09-14)

Regresses task token totals against the observed Δ in the provider's burned-window percentage.

```text
5h  group=provider  kept=112 dropped_reset=30 dropped_idle=41  r2=-0.2988 max_abs_corr=0.670 degenerate_pairs=0
5h  group=model     kept=112                                    r2=-0.2988 max_abs_corr=0.934 degenerate_pairs=0
7d  group=provider  kept=76  dropped_reset=2  dropped_idle=103 r2=-0.6072 max_abs_corr=0.659 degenerate_pairs=0
7d  group=model     kept=76                                     r2=-0.6066 max_abs_corr=0.913
```

Collapsing the three Anthropic model columns into one provider column cured the **collinearity**
(0.934 → 0.670) and did nothing for **R²**. Both stay solidly negative — worse than predicting the
mean. Five times the data that produced the same verdict the day before changed nothing.
Negative control (wrongly folding glm-flash into glm) degraded R² further, so the grouping step is
real and does something.

### Fit attempt 3 — `leadv2-codex-drain-fit.py`, merged as `259bdc7a` (2026-09-14)

codex has **zero** rows in `~/.claude/burn/history.db`'s `turn_events` — that writer is claude-code
sessions; codex runs under its own CLI. So a separate series was built from 332 timestamped
`util_codex=` readings in the lane journals, joined to confirmed token totals:

```text
provider=codex  kept=114 dropped_reset=2 dropped_idle=215 r2=-0.3974 max_abs_corr=0.000 degenerate_pairs=0
per_model       kept=61  r2=0.1456 max_abs_corr=0.402   gpt-5.6-terra=+0.0703 Δpct/1M tok, gpt-5.6-luna=0
```

`max_abs_corr=0.000` and `degenerate_pairs=0` — **no collinearity at all** — and R² is still
negative. That single line is the strongest evidence in this whole thread that collinearity was
never the disease.

## The question you are being paid to answer

**Why is R² negative even when the design matrix is provably not degenerate?**

A negative R² on a non-negative least squares means the model is systematically worse than a
constant. That is not a "needs more data" signature. Name the cause with a number. Candidates,
in the order I would check them — but the list is not binding and it is not exhaustive:

1. **The target is polluted by unattributed consumption.** The burned-window percentage is a
   property of the *account*, not of the lane. During any lane's interval the founder's own
   interactive sessions, the lead session, other lanes and any background tooling are draining the
   same bucket. If most of Δpct is other people's work, our tokens cannot explain it and the fit
   correctly reports that they don't. **Check:** quantify the share of Δpct attributable to the
   measured task's own tokens versus the residual. If the residual dominates, this is the answer
   and every observational fit on this shape is dead on arrival.
2. **The interval boundaries do not contain the work.** A reading is taken when the arbiter decides;
   the work runs afterwards, for minutes to an hour, and the next reading may land before or long
   after it finished. **Check:** compare interval length against actual task duration; report the
   distribution, not a mean.
3. **`dropped_idle` is throwing away the signal, not the noise.** 41 of 179 kept at 5h, 215 dropped
   at codex. A filter that discards most of the corpus needs its rule stated and its discarded set
   inspected before its output is trusted.
4. **The 7d window reads a source that retains 48h** (`retention_limit_h=48`,
   `~/.claude/burn/lib.py:8`). Say plainly whether a 7-day fit is even possible from it.
5. **No intercept / wrong functional form.** Fixed overhead per request (system prompt, tool
   schemas, cache reads) is not proportional to task tokens. If a real per-request constant exists,
   a through-the-origin model will fit worse than the mean by construction.

## Then: how do we actually get a price

Having named the cause, design the path. Judge every candidate on the same three axes: does it
produce a number we can defend, what does it cost to run, and what breaks if it is wrong.

Two candidates I already believe are live — treat them as starting points to confirm or kill, not
as the answer:

- **Published relative weights, the glm-flash route.** This is how the one honest price in the
  system was obtained. A prior lane checked `model-capability.yaml` and found nothing, which is not
  a search. Look at the actual authoritative surfaces: provider rate-limit and plan documentation,
  the CLI's own accounting or usage endpoints, any response header or usage field that reports
  consumption in provider units rather than tokens. Cite what you find with a URL or a file path
  and a live check, the way `:178` cites its source. **"Nothing authoritative exists" is a finding
  — state it that way, with what you looked at.** If relative weights exist, one free scale
  parameter per provider replaces three unknowns and the estimability problem disappears by
  construction while per-model resolution survives.
- **A controlled calibration probe instead of a regression.** Observational data is confounded;
  an experiment need not be. At a quiet moment: read the quota, issue a request of known size on a
  known model, read the quota again. Repeat N times per model. That is a direct measurement of
  Δpct per token, with no regression and no confounder — provided the account is genuinely idle,
  which is itself a thing you must verify, not assume. Cost it honestly: how many probes per model
  for a usable interval, what quota that burns, and whether the resolution of the percentage
  reading is even fine enough to see one request.

If a third path beats both, take the third path and say why.

## Binding method

- Every number carries its surface: the file, the table, the command that produced it.
- Every fit you quote carries R², `max_abs_corr`, `degenerate_pairs` and kept-count.
- **Do not write a price into `router_v2.cost`.** Not in this lane, under any circumstance. This
  lane produces a diagnosis and a designed path; a number lands only when the designed path has
  been run and its evidence reviewed. Six invented numbers (haiku 2, codex 3/4/7, sonnet 5,
  fable 8, opus 9) were believed for weeks and are exactly why this thread exists.
- An "almost free" or "roughly half" without an error bar is not a result.

## Known landmine — read before you propose writing anything

`router_v2.cost` keys its Anthropic entry `anthropic:` (`leadv2-routing.yaml:179`), but the
`capability_matrix` rows for haiku/sonnet/opus/fable carry `provider: claude` (:314-331), and both
`_price_key()` implementations (`lib/leadv2-launch-registry.py:277-278`,
`lib/leadv2-route-arbiter.sh:581-582`) return `c.get('provider')` verbatim for every row except
glm-flash. A real Anthropic price written under `anthropic:` would be looked up as `claude`, not
found, and silently replaced by the median — **behaviourally indistinguishable from `null`**.
Inert today only because the correct answer is `null`. Row filed:
`PRICE-KEY-ANTHROPIC-VS-CLAUDE-MISMATCH-01`. Do not fix it here; factor it into any plan that ends
in a written number.

## Acceptance

1. The negative-R² cause named with a number, not a hypothesis list. If several contribute, rank
   them by measured share.
2. An explicit verdict on whether ANY observational fit over this data shape can ever yield a
   defensible price — yes with the conditions, or no with the evidence.
3. A designed path to a real price: what to measure, on what surface, how many observations, what
   it costs to collect, and what the resulting number's error bar would be.
4. Published-weight search performed and reported with the surfaces examined, whether or not it
   found anything.
5. Still green: `test-arbiter-prices-by-provider.sh`, `test-codex-drain-fit.sh`,
   `test-codex-lane-token-total.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`.

## Off limits

- Writing any value into `router_v2.cost`.
- `reset_urgency`, the decision record schema, the launcher-refusal event, the judge parser.
- `~/.claude/burn/history.db`'s existing writer.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
