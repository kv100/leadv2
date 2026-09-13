# FIT-THE-PRICE-PER-PROVIDER-NOT-PER-MODEL-01

## The data blocker is gone; the tool is now the blocker

`d0282f6a0d13` (merge `39bf586c`) made codex lanes record a token total: 113 of 236 resolved, and
the joined corpus is now **sonnet=137, codex=113 pairs** — both far above the repo's own
`MIN_INTERVALS=12` floor. Waiting for more traffic is no longer the constraint.

Run today on that corpus, `leadv2-drain-weights.py` still cannot fit:

```text
window=5h  kept=112 threshold=12 r2=-0.2988 max_abs_corr=0.934 degenerate_pairs=5
window=7d  kept=76  threshold=12 r2=-0.6066 max_abs_corr=0.913 degenerate_pairs=5
weights: claude-haiku=0.0000059  claude-opus=0.00001453  claude-sonnet=0.0000101
         glm-5.3=0.0  glm-5.3-flash=0.00000168
```

Both R² are negative — worse than predicting the mean — with five times the data that produced the
same verdict on 2026-09-13. The diagnosis is in the same line: `max_abs_corr=0.934`,
`degenerate_pairs=5`.

**The reason is that the script fits PER MODEL.** Look at the weight names: `claude-haiku`,
`claude-opus`, `claude-sonnet` are three separate columns. They are not separable, because the
quota they drain is metered **per provider** — every Anthropic model burns one bucket. Three
columns describing one meter are linearly dependent by construction, and no volume of clean data
will ever separate them. That is exactly why the founder ruled on 2026-09-13 that price is
**per provider, not per model**, and the routing config already reflects it:

```yaml
router_v2.cost:
  glm-flash: 0.33     # measured
  glm:       1.0      # unit
  codex:     null     # UNPRICED
  anthropic: null     # UNPRICED
  freepool:  1.0
```

The arbiter reads it per provider too (`_price_key()` returns the provider, except glm-flash).
Only the FITTER was never converted. So the config asks a question the tool cannot answer.

## What to build

1. **A per-provider fit.** Collapse the model columns into their provider before fitting:
   `claude-haiku + claude-opus + claude-sonnet → anthropic`, `glm-5.3 → glm` (keep `glm-flash`
   separate — it has its own measured ratio and its own credit weight), codex → `codex`.
   Expect the collinearity to drop: three dependent columns become one. Report `max_abs_corr` and
   `degenerate_pairs` before and after — that comparison IS the evidence the change was the right
   one, not the R² alone.
2. **Keep fable separate, as its own LIMIT term, not its own price.** Fable has TWO windows
   (`weekly_all` and `weekly_scoped`); the current run already excludes it
   (`fable_intervals_excluded=11/13`). It shares the Anthropic price and constrains on its own
   scoped ceiling. Do not give it a price column.
3. **Report per provider, honestly.** For each of `anthropic`, `codex`, `glm`: the fitted weight,
   its R², the kept-interval count. **A provider whose R² stays negative gets NO price** — it keeps
   `null`, the arbiter keeps substituting the median, and that is recorded as the result. Do not
   ship a number you cannot defend; the whole reason this thread exists is that six such numbers
   (haiku 2, codex 3/4/7, sonnet 5, fable 8, opus 9) were once invented and believed for weeks.
4. **Then, only for providers that fit**, write the value into `router_v2.cost` and run the replay
   (`plugins/leadv2/scripts/leadv2-arbiter-replay.py`) over the recorded decisions. Report how many
   decisions changed. Zero changed is a publishable result: it would mean price does not
   discriminate on this corpus, and the arbiter is being driven by quota and capability alone.

## Watch for

- `dropped_idle=41` (5h) and `dropped_idle=103` (7d) — most intervals are discarded as idle. Check
  whether that filter is throwing away real work; a filter that keeps 76 of 179 intervals deserves
  one paragraph of justification before its output is trusted.
- `retention_limit_h=48` on the 7d window (`~/.claude/burn/lib.py:8`): the seven-day fit is reading
  a source that only retains 48h. Say plainly whether a 7d fit is even possible from it, or whether
  the 5h window is the only honest one today.
- `<synthetic>` appears as a weight column at 0.0. Find out what it is and whether it belongs in
  the fit at all.

## Method — binding

- Report R², `max_abs_corr`, `degenerate_pairs` and kept-count on EVERY fit you quote. A weight
  without its fit quality is the same mistake as the six invented numbers.
- Negative control: mutate the provider-collapsing step so two providers merge wrongly, show the
  fit quality degrades. A grouping change with no measurable effect on collinearity did not happen.
- Name the surface of every count.

## Acceptance

1. Per-provider fit output for `anthropic`, `codex`, `glm`, each with R², `max_abs_corr`,
   `degenerate_pairs`, kept-count — and a before/after collinearity comparison against the
   per-model fit above.
2. `router_v2.cost` updated ONLY for providers whose fit is defensible; the others stay `null`
   with the number that justifies staying.
3. If any price landed: the replay's changed-decision count.
4. Still green: `test-arbiter-prices-by-provider.sh`, `test-codex-lane-token-total.sh`,
   `test-reset-urgency.sh`, `test-arbiter-decision-record-inputs.sh`,
   `test-launcher-refusal-event.sh`, `test-leadv2-task-judge.sh`.
5. New suites registered so `tests/run-all.sh --scope changed` SELECTS them.

## Off limits

- Inventing a price for a provider that does not fit.
- `reset_urgency`, the decision record schema, the launcher-refusal event, the judge parser.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.

## AMENDMENT (founder question, 2026-09-14): collapse the FREE PARAMETERS, not the resolution

The founder pushed back on the premise: is per-provider actually better than per-model? The honest
answer is NO — per-model is physically correct (an opus token drains the Anthropic bucket faster
than a haiku token), and the per-model fit's own output shows plausible ratios:

```text
per 1M tokens:  haiku 5.9   sonnet 10.1   opus 14.5      (opus ~2.5x haiku)
```

Those ratios are believable but NOT trustworthy: `max_abs_corr=0.934` means the fit could have put
almost any other combination with the same sum in their place. We observe only the SUM of the three
— three unknowns, one equation.

So collapsing to a provider buys estimability at the cost of resolution. There is a third option
that keeps both, and we already use it elsewhere:

**glm-flash's 0.33 was never fitted. It came from Z.AI's published credit-weight ratio**
(`leadv2-routing.yaml:178`, founder ruling q-bba84179, 2026-09-02).

Do the same for Anthropic:

1. **Find whether relative per-model quota weights are published** for the Claude subscription
   (docs, rate-limit pages, the CLI's own accounting — whatever is authoritative). Cite the source
   with a URL or a file path, the way `:178` cites `docs.z.ai/devpack/teamplan.md`. If nothing
   authoritative exists, say so explicitly — that is a finding, not a failure.
2. **If the weights exist:** fit ONE free scale parameter per provider against
   `sum(model_tokens x known_relative_weight)`. One unknown instead of three: the collinearity is
   gone by construction, and per-model resolution is preserved. Report R2 and `max_abs_corr` for
   this shape too, and compare all three shapes side by side: per-model (today), per-provider
   (collapsed), and scale-times-known-weights (this one).
3. **If they do not exist:** fall back to the plain per-provider collapse as originally briefed,
   and record in the report that per-model resolution was LOST for lack of a published ratio — so
   the next person knows it is a data gap, not a design choice.

Same treatment for codex if its provider publishes anything comparable.

Ordering note: try (1) FIRST. If a published ratio exists, the collapsed fit is the inferior
fallback and should not be what lands.
