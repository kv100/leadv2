verdict: APPROVE
next_action: continue

# FIT-THE-PRICE-PER-PROVIDER-NOT-PER-MODEL-01 — developer report

## What changed

`plugins/leadv2/scripts/leadv2-drain-weights.py`:
- Added `_PROVIDER_PREFIXES` + `_provider_for_model(model)`: maps
  `claude-haiku*`/`claude-opus*`/`claude-sonnet*` → `anthropic`, `glm-5.3` →
  `glm`, `glm-5.3-flash` → `glm-flash` (kept separate — its own measured
  credit ratio, GLM-EFFICIENCY-01), `codex*` → `codex`, anything unrecognised
  → itself (never silently dropped).
- Added `--group model|provider` CLI flag, default `provider`. `model` keeps
  the exact pre-existing one-column-per-raw-model-name behaviour, needed for
  the before/after collinearity comparison below.
- A `turn_events.model == "<synthetic>"` row is now always dropped before
  either grouping, counted in the output as `synthetic_rows_dropped=N`.
- Output line now also reports `group=<mode>`.

No other file was touched. `router_v2.cost` is UNCHANGED — see "Why no price
landed" below.

## `<synthetic>` — what it is (mission's watch-item)

```
$ sqlite3 -header -column ~/.claude/burn/history.db \
  "SELECT ts, session_id, account_key, input, output, tools_json FROM turn_events WHERE model='<synthetic>' ORDER BY ts;"
ts                         session_id                            account_key  input  output  tools_json
2026-09-12T01:34:32.652Z   b37e2cc6-7d26-4e77-898e-4ee362ea960e  eb6c5b97     0      0       []
2026-09-12T01:36:48.934Z   a9e9cc5f-259c-4370-a03e-9252540e2368  eb6c5b97     0      0       []
... (7 rows total, all input=0 output=0)
```
Every `<synthetic>` row carries zero tokens. It cannot carry fit signal
(its column in X is always the zero vector), so it never earned a non-zero
weight — it was pure report noise, not a data problem. Dropped it explicitly
rather than let it survive as a decorative all-zero row. Its own origin
(what synthesizes it) is inside the Claude Code harness itself
(`~/.claude/burn/*.py`, outside this plugin's tree and outside this task's
scope) — not chased further since the token evidence alone settles whether
it belongs in the fit.

## codex — why it never appears (mission's premise, re-examined)

```
$ sqlite3 ~/.claude/burn/history.db "SELECT model, count(*) FROM turn_events GROUP BY model;"
<synthetic>|7
claude-fable-5-1|210
claude-haiku-4-5-20251001|498
claude-opus-5|2288
claude-sonnet-5|426
glm-5.3|3031
glm-5.3-flash|254
```
No `codex` row has ever existed in `turn_events` for this account. This
fitter's corpus is `rate_limit_history` (Anthropic-account Δpct,
`account_key` values are Claude Max account ids: `eb6c5b97`, `5a3c2328`,
`47fc2659`, `default` — confirmed `PRAGMA table_info` has no `provider`
column, i.e. it is Anthropic-only) joined against `turn_events` token counts
inside the same account/session. Codex is a separate CLI that never writes a
Claude Code turn event, so a `codex` provider column in this fit is not
"doesn't fit" — it is undefined, zero-tokens-forever, by construction of the
data source, not a volume problem.

The mission's opening reference ("sonnet=137, codex=113 pairs") is a
DIFFERENT corpus: `d0282f6a0d13` made codex *arbiter decision records*
(replay corpus, joined via `leadv2_lane_token_total` in
`lib/leadv2-cost-actuals.sh`, reading `~/.codex/sessions/**/rollout-*.jsonl`
token_usage_records) carry a real token total. That corpus feeds
`leadv2-arbiter-replay.py` for counterfactual re-scoring of past decisions —
it has nothing to do with `rate_limit_history`/`turn_events`, and cannot
supply this fitter with a `codex` Δpct-vs-tokens column. Confirmed by
`test-codex-lane-token-total.sh` (passing, 9/9) which exercises exactly that
join, entirely separate from `leadv2-drain-weights.py`.

Aside, not acted on (out of the mission's "what to build" list, flagged for
awareness): `leadv2-quota-daemon.py` does maintain a per-provider
`provider_quota_history` table (`used_pct` per provider+window) that WOULD
be the structurally-correct source for a future codex/glm fit. Live check:
```
$ sqlite3 ~/.claude/burn/history.db \
  "SELECT provider, window, count(*), min(captured_epoch), max(captured_epoch) FROM provider_quota_history GROUP BY provider, window;"
codex|primary|24|1789319320.09644|1789321321.50337
glm|five_hour|24|1789319320.09379|1789321321.48685
glm|weekly|24|1789319320.09379|1789321321.48685
```
24 rows spanning ~33 minutes — far below `MIN_INTERVALS=12` *kept* (after
idle/reset filtering it would be far fewer), and it is not currently joined
to any per-interval token source at all. Building that join is a new
feature, not a fix to the existing fitter — left alone as scope creep beyond
this task's "what to build" list.

## Per-provider fit output (live run, this repo, 2026-09-14)

```
=== 5h provider (NEW) ===
window=5h account=eb6c5b97 group=provider kept=112 threshold=12 dropped_reset=30 dropped_idle=41 fable_intervals_excluded=11 synthetic_rows_dropped=7 r2=-0.2988 max_abs_corr=0.670 degenerate_pairs=0 weights=anthropic=0.00001301,glm=0.00000000,glm-flash=0.00000149 snapshots=195
  anthropic                    weight=0.00001301 Δpct per token  (per 1M tokens: +13.0147)
  glm                          weight=0.00000000 Δpct per token  (per 1M tokens: +0.0000)
  glm-flash                    weight=0.00000149 Δpct per token  (per 1M tokens: +1.4924)

=== 5h model (OLD/legacy, for comparison) ===
window=5h account=eb6c5b97 group=model kept=112 threshold=12 ... r2=-0.2988 max_abs_corr=0.934 degenerate_pairs=0 weights=claude-haiku-4-5-20251001=0.00000590,claude-opus-5=0.00001453,claude-sonnet-5=0.00001010,glm-5.3=0.00000000,glm-5.3-flash=0.00000168 snapshots=195

=== 7d provider (NEW) ===
window=7d account=eb6c5b97 group=provider kept=76 threshold=12 dropped_reset=2 dropped_idle=103 fable_intervals_excluded=13 synthetic_rows_dropped=7 r2=-0.6072 max_abs_corr=0.659 degenerate_pairs=0 weights=anthropic=0.00000317,glm=0.00000000,glm-flash=0.00000000 snapshots=195 retention_limit_h=48 (~/.claude/burn/lib.py:8 TURN_EVENTS_RETENTION_HOURS)

=== 7d model (OLD/legacy, for comparison) ===
window=7d account=eb6c5b97 group=model kept=76 threshold=12 ... r2=-0.6066 max_abs_corr=0.913 degenerate_pairs=0 weights=claude-haiku-4-5-20251001=0.00000000,claude-opus-5=0.00000404,claude-sonnet-5=0.00000000,glm-5.3=0.00000000,glm-5.3-flash=0.00000000 snapshots=195 retention_limit_h=48
```

codex never appears as a column in either mode — zero data (see above).

## Before/after collinearity comparison (Acceptance #1)

| window | max_abs_corr (per-model) | max_abs_corr (per-provider) | R² (per-model) | R² (per-provider) |
|---|---|---|---|---|
| 5h | 0.934 | **0.670** | -0.2988 | -0.2988 |
| 7d | 0.913 | **0.659** | -0.6066 | -0.6072 |

Collapsing the three Anthropic model columns into one `anthropic` column DID
cut the worst pairwise collinearity roughly by a third in both windows, as
predicted (three dependent columns describing one meter really were most of
the correlation). What it did NOT do is rescue R²: identical at 5h (the
extra per-model degrees of freedom bought zero additional fit — consistent
with "no amount of clean data separates them", since if it could, per-model
R² would have exceeded per-provider R²) and marginally *worse* at 7d
(-0.6066 → -0.6072, noise-level, not a real regression). **The diagnosis in
the mission holds only for the collinearity symptom, not for R²**: even with
the meter-aligned grouping, Δpct-per-token is not linearly explained by
token volume on this corpus. `dropped_idle` is large in both windows
(41/153 5h, 103/179 7d) — see "watch item" below; even generously assuming
every dropped interval would have added signal, the sign and magnitude of
R² (both windows solidly negative, i.e. worse than predicting the mean)
would not plausibly flip from adding more of the same idle/zero-token
intervals.

## Negative control (Acceptance's "Method — binding" requirement)

Wrongly folded `glm-5.3-flash` into `glm` (the collapse the mission
explicitly says NOT to do, since glm-flash has its own measured
GLM-EFFICIENCY-01 ratio) and re-ran the 5h fit:

```
=== 5h WRONG-MERGE (glm-flash folded into glm) ===
window=5h account=eb6c5b97 group=provider kept=112 threshold=12 ... r2=-0.2990 max_abs_corr=0.630 degenerate_pairs=0 weights=anthropic=0.00001324,glm=0.00000000
```

vs. the correct grouping's `r2=-0.2988 weights=anthropic=...,glm=0.0,glm-flash=0.00000149`.

Effect: R² got (marginally) *worse*, -0.2988 → -0.2990 — mathematically
guaranteed to be able to only degrade or tie, never improve, because merging
two real columns is a strict restriction of the NNLS feasible space — and
the one non-zero, defensible-looking secondary weight the correct grouping
produced (`glm-flash=+1.49/1M tokens`) is completely erased, indistinguishable
from `glm`'s already-zero weight. This is the demonstration the mission asks
for: a wrong provider merge measurably costs fit quality and destroys a real
signal; it did not merely "have no effect."

## Why no price landed (Acceptance #2)

Per the mission's own rule ("A provider whose R² stays negative gets NO
price"):
- **anthropic**: R² -0.2988 (5h) / -0.6072 (7d), both negative. NO price.
- **glm**: weight=0 in every run (5h and 7d, both groupings) — never wins
  any positive NNLS weight against this target. NO price.
- **codex**: zero rows in the corpus, ever (see above) — not evaluated, NO
  price (there is nothing to defend or refuse; the column doesn't exist).

`router_v2.cost` (`plugins/leadv2/config/leadv2-routing.yaml:177`) is
therefore left byte-identical: `anthropic: null`, `codex: null`. This is the
"zero changed" outcome the mission names as publishable: on this corpus,
price does not discriminate for anthropic/glm/codex, and the arbiter's
existing `matrix_median` unpriced-policy plus quota/capability signals are
what's actually driving those arms today.

## Landmine found, NOT fixed (flagging per "if your change contradicts a
comment, say so" instruction — genuinely out of this task's scope since no
price landed to expose it)

`router_v2.cost` keys its Anthropic entry `anthropic:`
(`leadv2-routing.yaml:179`), but the capability_matrix rows for
haiku/sonnet/opus/fable carry `provider: claude`
(`leadv2-routing.yaml:314-331`), and both `_price_key()` implementations
(`lib/leadv2-launch-registry.py:277-278` and
`lib/leadv2-route-arbiter.sh:581-582`) return `c.get('provider')` verbatim
for every row except `glm-flash`. So **if `anthropic:` in `router_v2.cost`
were ever set to a real number, `_price_key` would look it up under `claude`
and never find it** — it would silently fall through to `_COST_MEDIAN`
instead, exactly as it does today with `null`. The two values (real price vs
null) would be indistinguishable in the arbiter's behavior. This is inert
right now only because the correct fit result is "leave it null" — the
moment any future run of this tool produces a defensible Anthropic number,
this key mismatch must be fixed first (either rename the yaml key to
`claude` or teach `_price_key` to normalize `claude`→`anthropic`), or the
number will be written and silently ignored. Not touched here: it changes
`_price_key()`, which is shared production pricing logic well beyond this
task's file list, and doing so with no real price to test it against would
be an unverified, unverifiable change.

## Falsification set

```
$ python3 -m py_compile plugins/leadv2/scripts/leadv2-drain-weights.py
(exit 0, no output)
```
No `.sh` files were changed (only `leadv2-drain-weights.py`), so `bash -n`
is not applicable to this diff.

## Required regression suites — full output

```
##### plugins/leadv2/tests/test-arbiter-prices-by-provider.sh #####
PASS: (1) cheaper provider (glm 1.0 < codex 5.0) wins, cost_src=glm:measured
PASS: (2) negative control: prices swapped -> arm=codex wins (proves the price is actually read)
PASS: (3) null price -> arm still selected (never refused), cost_src=glm:median
PASS: (4) cost: block absent -> legacy row cost honoured, cost_src=codex:legacy_row
PASS: (5) max_cost=2 excludes codex (provider price 5.0 > 2) -> arm=glm
PASS: (5b) same max_cost against swapped prices -> exclusion flips to arm=codex
PASS: (6) malformed router_v2.cost.codex -> rc=2, reason=routing_yaml_invalid names the key
SUMMARY pass=7 fail=0

##### plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh #####
PASS: 0 bash -n lib/leadv2-cost-actuals.sh
PASS: 1 codex rollout join sums input+output = 990
PASS: 2 two codex spawns sum across threads = 1320 (990+330)
PASS: 3 ambiguous >1 rollout match -> '-' (never guesses a sibling's file)
PASS: 4 no job json for handle -> '-'
PASS: 5a no artifacts at all -> no_seam_for_arm
PASS: 5b codex handle but unresolved rollout -> costs_yaml_absent
PASS: 5c only sessions.map, no burn db -> turn_events_empty
PASS: 5d costs.yaml exists but unparseable -> parse_failed
SUMMARY pass=9 fail=0

##### plugins/leadv2/scripts/tests/test-reset-urgency.sh #####
PASS: (a) founder case: weekly Claude reset in 5h with 95pct left outranks Codex reset in 140h
PASS: (b) near reset with only 2pct left is not preferred
PASS: (c) unreadable reset is neutral (no Claude urgency token)
PASS: (d) negative and zero reset values are neutral, not stale-cache boosts
PASS: (e) non-binding five-hour meter supplies urgency while weekly remains binding
PASS: (f) same frozen decision twice is byte-identical (no reset oscillation)
PASS: (g) urgency cannot buy capability: unsupported Claude docs arm is absent
PASS: (h) kill switch restores cost order and removes urgency provenance
PASS: (i RED) removing the urgency formula flips the founder case to codex
PASS: (i GREEN) unmutated arbiter restores the founder-case Claude pick
SUMMARY: pass=10 fail=0

##### plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh #####
PASS: arbiter success line carries the replay inputs
PASS: schema-v2 record contains winner inputs, both candidates, and exclusion reasons
PASS: complexity replay moves the recorded decision from capable to cheap
PASS: replay refuses output-only schema-v1 rows
PASS: estimate records the dispatch signature used by its terminal actual
PASS: cost_actual carries the reciprocal estimate_task_id join key
SUMMARY pass=6 fail=0

##### plugins/leadv2/scripts/tests/test-launcher-refusal-event.sh #####
PASS: plugin kind is normalized by the real launch registry; a separate real refusal reached dispatcher capture seam
PASS: decision journal row joins sig8, arm, reason, and actual fallback
PASS: durable event row carries exact launcher refusal and fallback
PASS: RED control: mutating capture reason made the real-refusal assertion red
launcher-refusal-event: PASS=4 FAIL=0

##### plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh #####
=== Results: 36 passed, 0 failed ===
```
All six green: 7+9+10+6+4+36 = 72 assertions, 0 failures. None of these
suites exercise `leadv2-drain-weights.py` directly (no test file for it
exists in the repo — confirmed by `find . -iname '*drain-weight*'` returning
only the script itself); they are green because this change touched no
production pricing/decision path, only the standalone diagnostic fitter.

## Acceptance checklist

1. Per-provider fit output for anthropic/codex/glm with R², max_abs_corr,
   degenerate_pairs, kept-count, and before/after collinearity comparison —
   done, above.
2. `router_v2.cost` updated only for defensible fits — none were defensible;
   left unchanged (verified: `git diff` shows zero touch to
   `leadv2-routing.yaml`).
3. Replay changed-decision count — N/A, no price landed, so
   `leadv2-arbiter-replay.py` was not run (nothing to replay against).
4. Six required suites green — done, above (72/72 assertions).
5. New suites registered — N/A, no new `test-*.sh` suite was added. Left
   alone deliberately: the mission's "what to build" list is a diagnostic
   fitter + a manual, conditional yaml edit, not a new gate; the six
   suites already named cover the arbiter/decision-record surfaces this
   change could plausibly regress, and none of them import or exercise
   `leadv2-drain-weights.py`. If a future run of this tool does produce a
   defensible price, that yaml edit and the arbiter's `_price_key` landmine
   above are the next lane's starting point, not this one's.

## What I deliberately left alone

- The `claude`/`anthropic` `_price_key` naming mismatch (landmine, flagged
  above) — inert today, would need its own verified fix + test the day a
  real Anthropic price exists.
- `provider_quota_history` (the structurally-correct per-provider Δused_pct
  source for a future codex/glm fit) — noted as an aside, not built into a
  new fitter; that is a new feature, not this task's scope.
- No automated regression test added for `leadv2-drain-weights.py --group`
  itself (none existed before this change either).

DELIVERABLE_COMPLETE
