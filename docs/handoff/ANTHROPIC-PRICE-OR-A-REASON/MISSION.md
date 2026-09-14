# ANTHROPIC-PRICE-OR-A-REASON-WE-CANNOT-HAVE-ONE-01

Founder order, 2026-09-14, sibling to `HOW-DO-WE-EVER-GET-A-PRICE-01` (row `2bbf42c25145`, running
on codex/astra). That lane owns the general question "why is R² negative" and the codex half.
**You own the Anthropic half**, which is a genuinely different problem — see below. Do not
re-litigate codex; do not touch `leadv2-codex-drain-fit.py`.

You are running ON the provider you are measuring. That is the reason this lane is a Claude arm and
not a codex one, and it is an asset you are expected to use — see item 4.

## What is already measured — do not re-derive any of this

The arbiter's cost term is per PROVIDER (founder ruling 2026-09-13). `router_v2.cost`
(`plugins/leadv2/config/leadv2-routing.yaml`): `glm-flash: 0.33`, `glm: 1.0`, `codex: null`,
`anthropic: null`, `freepool: 1.0`. A `null` price falls through to `_COST_MEDIAN` = 1.0, so
anthropic, codex and glm are priced identically today. **glm-flash's 0.33 was never fitted** — it is
Z.AI's published credit-weight ratio (`leadv2-routing.yaml:178`, founder ruling q-bba84179,
citing `docs.z.ai/devpack/teamplan.md`). It is the only price in this system with a defensible
origin, and copying its method is the highest-value thing you can do.

`~/.claude/burn/history.db`'s `turn_events`, by model: `claude-opus-5` 2288, `claude-haiku-4-5`
498, `claude-sonnet-5` 426, `claude-fable-5-1` 210, plus `glm-5.3` 3031 and `glm-5.3-flash` 254
(GLM appears because it physically runs THROUGH claude-code with a redirected base URL). No
`gpt-5.6-*` row has ever existed there.

`leadv2-drain-weights.py` (merged `b78bb547`) regresses task token totals against the observed Δ in
the burned-window percentage:

```text
5h  group=provider  kept=112 dropped_reset=30 dropped_idle=41  r2=-0.2988 max_abs_corr=0.670 degenerate_pairs=0
5h  group=model     kept=112                                    r2=-0.2988 max_abs_corr=0.934 degenerate_pairs=0
7d  group=provider  kept=76  dropped_reset=2  dropped_idle=103 r2=-0.6072 max_abs_corr=0.659 degenerate_pairs=0
7d  group=model     kept=76                                     r2=-0.6066 max_abs_corr=0.913
per 1M tokens (per-model, 5h): haiku 5.9   sonnet 10.1   opus 14.5
```

Collapsing haiku/opus/sonnet into one `anthropic` column cured the collinearity (0.934 → 0.670) and
did nothing for R². The ratios above are physically plausible and **not trustworthy**:
`max_abs_corr=0.934` means almost any other combination with the same sum would fit equally well.

**The decisive cross-check, from the codex lane:** codex's own series fits at `kept=114
r2=-0.3974` with `max_abs_corr=0.000` and `degenerate_pairs=0` — no collinearity whatsoever — and
R² is still negative. So collinearity was never the disease. Whatever is wrong is wrong for a
different reason, and Anthropic has that reason too, on top of its own.

## What is Anthropic-specific — your four items

1. **Four models, one meter, and it actually matters here.** codex's per-model fit is not
   collinear (`max_abs_corr=0.402`); Anthropic's is (`0.934`). Anthropic is the only provider where
   per-model resolution is both physically real and structurally unestimable from observation. So
   the published-weight route matters more here than anywhere.

2. **Search for published relative per-model quota weights — properly.** A prior lane checked
   `model-capability.yaml`, found nothing, and stopped; that is not a search. Look at the
   authoritative surfaces: the subscription's rate-limit and plan documentation, the CLI's own
   usage accounting and any local telemetry it writes, and any usage field or response header that
   reports consumption in *provider units* rather than tokens. If the API or CLI reports anything
   normalised — credits, units, weighted tokens, a cost field — that IS the published weight and
   the problem dissolves. Cite what you find with a URL or a file path plus the live check that
   confirmed it, the way `:178` cites its source. **"Nothing authoritative exists" is a finding,
   not a failure — state it that way, listing what you examined.** If weights exist, fit ONE free
   scale parameter per provider against `sum(model_tokens × known_relative_weight)`: one unknown
   instead of four, collinearity gone by construction, per-model resolution preserved.

3. **Nested windows — the hypothesis only Anthropic has.** Claude is governed by more than one
   meter at once: a five-hour window and a seven-day window (both already visible in the arbiter's
   own `reset_urgency=claude:…[five_hour]` / `[seven_day]` output), and fable additionally carries
   its own scoped weekly ceiling (`weekly_all` and `weekly_scoped`, live as
   `util_claude_fable=… scoped_window_fable=weekly_scoped(fable)`). The fit reads a percentage off
   ONE window. If the same token spend produces a different Δpct depending on which window is
   binding, on how near that window is to reset, or on which of several meters the reading came
   from, then the target variable is not a single quantity and no regression on it can converge.
   **Check it**: does Δpct per token differ systematically by window, by time-to-reset, or by which
   meter was read? Report the comparison, not an assertion. The existing fitter already drops
   reset-spanning intervals (`dropped_reset=30` at 5h) — that is a different and narrower concern;
   do not confuse the two.

4. **You are inside the bucket you are measuring — use it.** Every request this lane makes drains
   the same Anthropic meter it is studying, and you know your own token counts exactly. That makes
   a controlled calibration possible without any regression: read the quota, issue a request of
   known size on a known model, read the quota again, repeat. Confounders you must handle rather
   than assume away: the account is shared with the founder's interactive sessions, the lead
   session and other lanes, so "idle" is a condition to VERIFY, not to hope for; and the percentage
   reading has a finite resolution which may be coarser than a single request. Cost it honestly —
   how many probes per model for a usable interval, and what quota that burns. If the resolution
   makes it impossible, say so with the number that makes it impossible; that is a real answer.

## Binding method

- Every number carries its surface: the file, the table, the command that produced it.
- Every fit you quote carries R², `max_abs_corr`, `degenerate_pairs` and kept-count.
- **Do not write a price into `router_v2.cost`.** Not in this lane, under any circumstance. Six
  invented numbers (haiku 2, codex 3/4/7, sonnet 5, fable 8, opus 9) were believed for weeks and
  are exactly why this thread exists. A number lands only after a designed path has been run and
  its evidence reviewed.
- A ratio without an error bar is not a result.
- **Never print a token, key or session value.** Probes report HTTP status and error type only.

## Known landmine — this one is Anthropic's

`router_v2.cost` keys its Anthropic entry `anthropic:` (`leadv2-routing.yaml:179`), but the
`capability_matrix` rows for haiku/sonnet/opus/fable carry `provider: claude` (:314-331), and both
`_price_key()` implementations (`lib/leadv2-launch-registry.py:277-278`,
`lib/leadv2-route-arbiter.sh:581-582`) return `c.get('provider')` verbatim for every row except
glm-flash. A real Anthropic price written under `anthropic:` would be looked up as `claude`, not
found, and silently replaced by the median — **behaviourally indistinguishable from `null`**. Inert
today only because the correct answer is `null`. Row filed:
`PRICE-KEY-ANTHROPIC-VS-CLAUDE-MISMATCH-01`; do not fix it here, but any plan of yours that ends in
a written number must account for it.

## Acceptance

1. The published-weight search performed and reported with the surfaces examined, found or not.
   If found: the scale-times-known-weights fit, with R² and `max_abs_corr` beside the per-model and
   per-provider shapes for comparison.
2. The nested-window hypothesis tested with a number: does Δpct per token vary by window, by
   time-to-reset, or by which meter was read — and by how much.
3. A designed path to a defensible Anthropic price: what to measure, on what surface, how many
   observations, what it costs to collect, and what the resulting number's error bar would be. Or
   an evidenced statement that no such path exists, which is equally publishable.
4. Still green: `test-arbiter-prices-by-provider.sh`, `test-codex-drain-fit.sh`,
   `test-codex-lane-token-total.sh`, `test-reset-urgency.sh`,
   `test-arbiter-decision-record-inputs.sh`, `test-launcher-refusal-event.sh`,
   `test-leadv2-task-judge.sh`.
5. Any new suite registered so `tests/run-all.sh --scope changed` SELECTS it.

## Off limits

- Writing any value into `router_v2.cost`.
- `leadv2-codex-drain-fit.py` and anything codex-specific — the sibling lane owns it.
- `reset_urgency`, the decision record schema, the launcher-refusal event, the judge parser.
- `~/.claude/burn/history.db`'s existing writer.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
