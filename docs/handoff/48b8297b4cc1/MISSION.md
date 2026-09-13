# ARBITER-DECISION-INPUTS-01 — the inputs the founder asked for, measured before built

## Why this exists

The founder listed, in his own words, what the arbiter must weigh when it picks an arm:

> «стоит учитывать достпность квоты как недельной так и 5 часово (в кодексе нет 5 часовой),
> воможностит модели, тип задачи, сложность задачи, оценку сколько задача сожрет токенов и тд…
> Так же конечно если "скоро" сброс квоты то стоит исопльзщовать этот провайдер это тоже будет
> эффективно… чтобы они общались и принимали лучшее решенеи… Кажется что стоит сузественно
> добавить гранялрности почт ивезде»

and gave the worked case he wants handled:

> «условно остался 5 часов до обновления недельной квоты claude и лучше максимально брать его в
> работу овер других так как скоро обнуление»

A sibling lane (`cc4557feef48`, `ARBITER-PRICE-IS-PER-PROVIDER-NOT-PER-MODEL-01`) covers PRICE and
only price. This lane covers the DECISION INPUTS. Do not re-derive price here; read the sibling's
result if it has landed, and if it has not, treat `cost` as a black box you do not touch.

## What is already true (measured 2026-09-13 — verify by spot-check, do not re-derive from scratch)

Read `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`.

PRESENT:
- Both windows. `WINDOW_PERIOD_HOURS={'five_hour':5.0,'weekly':168.0,'seven_day':168.0,'weekly_scoped':168.0}`
  at :608; `weekly_scoped` (fable's own bucket) at :646; `windows.pop('seven_day', None)` at :727.
  Codex having no 5h window is handled by the window simply being absent, not by a special case.
- Reset proximity, but ONLY as a permission to WAIT. `near_reset_wait(provider, arm=None)` at :779
  is called in exactly two places — `:1049` and `:1072` — and both read
  `over_ceiling(p) and near_reset_wait(p)`. That is: "this provider is already past its ceiling,
  but its window resets soon, so hold rather than exclude". It is NOT a preference in the ranking.
- Expected spend, in HOURS. The `W1-FORECAST-THE-SPEND-01` block at :784 forecasts
  `expected_hours` = p75 of wall-clock spawn→terminal durations from the events journal, and
  compares it against the remainder of EVERY readable window. Live line today:
  `forecast_hours=2.32h forecast_basis=journal:provider=191 forecast_stat=p75`.
- Task type and complexity. `complexity=complex complexity_source=judge conf=0.9 req_eff=4.0
  fit_mode=on fit_pick=… fit_differs=0`. The complexity estimate comes from
  `plugins/leadv2/scripts/leadv2-task-judge.sh`, a separate service the arbiter consults.
- Model capability. `router_v2.capability_matrix` in `plugins/leadv2/config/leadv2-routing.yaml`.

ABSENT — zero matches for `token_estimate|est_tokens|expected_tokens|size_estimate` anywhere in
the arbiter:
- Any estimate of how many TOKENS the task will consume. The forecast is hours of wall clock,
  which includes an open lane's idle time and says nothing about burn.

## The five deliverables

Each one is a SEPARATE, INDEPENDENTLY REVERTIBLE change with its own suite. If you can only
finish some, finish those completely and say which you did not reach — never half-land all five.

### D1 — reset proximity must PREFER, not merely permit

Today a provider whose window resets in 3 hours ranks exactly like one whose window resets in 130,
unless it is already over its ceiling. The founder's case is the opposite: quota about to be
thrown away is quota that should be spent NOW.

Build a `reset_urgency` term that enters the ranking. Requirements:
- It is a function of `hours_to_reset / period_hours`, so a 5h window at 1h-to-reset and a weekly
  window at 33h-to-reset are the same urgency. Never a raw hours threshold.
- It applies to the quota that would actually be WASTED: urgency is proportional to the REMAINING
  fraction of that window. A provider resetting in 1h with 2% left has nothing to donate; one
  resetting in 1h with 80% left is the founder's case exactly.
- It is bounded, and you state the bound as a number the way headroom does
  (`_HEADROOM_W_MIN=0.2/_HEADROOM_W_MAX=1.0` gives at most 5×). A term that can swamp capability
  is a bug.
- `remaining_pct` IS remaining, not consumed — `~/.claude/burn/quota-fragment.sh` does
  `pct = d.get("remaining_pct")`. Get this backwards and the whole term inverts.

Edge cases you must build and run, not reason about:
- `hours_to_reset` is None (unreadable window) — must be neutral, never a free boost.
- The reset already passed but the cache is stale (negative or ~0 hours).
- Two providers both near reset — the term must not make the pick oscillate between runs; prove
  determinism by running the same decision twice with a frozen clock.
- A provider near reset that is NOT capable of the task — urgency must never buy capability.
- The 5h window near reset while the weekly window is the binding one. Which one's urgency counts?
  Decide, write down why, and prove the other case is not silently ignored.

### D2 — an estimate of the task's TOKEN size

The founder asked for it by name and it does not exist. Build it.

- The estimate must be MEASURED, never a hand-picked constant. The same events journal the
  forecast block already reads carries real runs; `docs/handoff/*/cost-estimate.yaml` is already
  written per dispatch (`cost_estimate_recorded … path=docs/handoff/<row>/cost-estimate.yaml`).
  Start by reading what those files already contain — the machinery may be half-built.
- Inputs available BEFORE spawn: mission character count (the dispatcher already logs
  `chars=30562` in `kimi_skipped`), the prepass write set size, complexity class, duration class,
  phase list. Fit against observed actual token spend per run.
- Report the fit HONESTLY. If R² is bad, the deliverable is "the estimate is not derivable from
  these inputs, here is the number that proves it" — a bad estimate wired into routing is worse
  than none. The price lane already produced one such honest negative (5h kept=99 R²=−0.3152,
  7d kept=61 R²=−0.7937, max_abs_corr=1.000, degenerate_pairs=7), and that negative is what let
  the founder decide correctly. You are allowed to return a negative. You are not allowed to
  return a number you cannot defend.
- If it IS derivable: feed it to the SAME comparison the hours-forecast already makes against
  window remainders, so "will this task fit in what is left" is answered in tokens, not only hours.

### D3 — granularity, made concrete

«сузественно добавить гранялрности почт ивезде» is not actionable as written. Turn it into a
census first, then a change:
- Enumerate every axis the decision currently collapses. Known starters: `complexity` is a
  3-value bucket; `duration_class` is short/medium/long; `req_eff` is a single float; quota is
  per-provider with fable the only sub-bucket; `fit_bucket` shows ties as `sonnet:0,codex:0,codex:0`.
- For EACH axis, answer with evidence: does a finer value change any of the ~130 recorded routing
  decisions? An axis whose refinement moves zero decisions must be reported as "refining this
  changes nothing" and left alone. This is the acceptance test for the whole deliverable: a
  granularity change that moves no decision is not an improvement, it is new surface area.
- Land refinement only on the axes where the replay shows movement, and report the movement count.

### D4 — the services must be smart, and must talk

The founder: «я просил не раз архитекторов сделать эти сервисы Умными даже если надо делать ллм
запрос (апи ключ глм может исопльзоваться для этого) и чтобы они общались и принимали лучшее решение».

Measured state: a judge→arbiter conversation ALREADY exists — `leadv2-task-judge.sh` estimates task
hardness and the arbiter consumes it (`complexity_source=judge`), and the judge deliberately carries
"ZERO arm/model/provider/quota vocabulary" (:11) so the two stay separable. That boundary is good
design; do not collapse it.

Two real gaps:
1. The judge runs on **haiku** (`JUDGE_MODEL="${LEADV2_JUDGE_MODEL:-haiku}"`, :60) — the decision
   layer spends ANTHROPIC quota to decide how to spend Anthropic quota. The founder explicitly
   offered the GLM key for exactly this. Make the judge's arm configurable and default it to a GLM
   model, keeping the haiku path as fallback. Prove with a live judge call on each path that the
   verdicts agree on a fixed set of ≥10 real missions, and report the disagreement count. If GLM
   disagrees materially, say so and keep haiku — do not ship a cheaper judge that is worse.
2. There is no service that reasons about the QUOTA PICTURE as a whole. Design (do not necessarily
   build in this lane — say which) a second consultation: given the full window census across all
   providers plus the task estimate, one cheap LLM call returns a recommendation and a one-line
   reason, which the arbiter treats as ONE input among the deterministic terms and logs. It must
   never be able to override capability or protection. The deterministic path must produce the
   same answer when the call fails or times out — prove it by forcing a failure.

Standing constraint: `feedback_decision_layer_may_spend_to_decide_well` — the founder has already
ruled that the decision layer is allowed to spend in order to decide well. Cost is not the reason
to skip an LLM call here. Being unable to prove it helps is.

### D5 — method

The founder asked for the method explicitly: «стоит много искать, перепроверять, делать пробы,
строить едж кейсы, проверять то что кажется верным и то что кажется не верным».

Concretely, for every claim you make in the deliverable:
- A claim about the arbiter's behaviour carries the decision line it was read from, or a replay.
- A claim that something is ABSENT carries the exact search that returned nothing.
- Every term you add gets a NEGATIVE CONTROL: mutate the term inside the function body in a
  scratch worktree, show the suite goes red, restore. A suite that stays green under mutation is
  not a suite. Known trap: a mutation whose target text appears in a comment can rot into a
  permanent green — mutate the code line, strip comments when grepping.
- Re-check the things that look obviously true. Two measured examples from today that looked
  obviously true and were not: `unknown_capped` was silently excluding codex from 122 of 143
  decisions, and a probe registered with a relative path reads rc=127 exactly like a broken probe.

## Acceptance

1. A replay harness over the recorded routing decisions (there are ~130 in the events journal;
   the price lane builds the same kind of replay — reuse it if it landed, and say so).
   For each deliverable, the replay reports HOW MANY decisions changed and WHICH. A deliverable
   that changes zero decisions is reported as changing zero decisions, not quietly shipped.
2. The founder's worked case runs as an explicit test: Claude weekly at ~5h to reset with
   substantial headroom left, competing against codex at ~140h to reset. The test asserts Claude
   is preferred, and a sibling test asserts it is NOT preferred when its remaining fraction is
   near zero. Both in one suite.
3. Every new suite is registered so `tests/run-all.sh --scope changed` SELECTS it — prove it by
   committing first, then showing the selection output. `git diff --name-only origin/main...HEAD`
   is what drives selection: uncommitted work is invisible to it.
4. The deliverable states, per founder input, one of: BUILT (with the replay delta), MEASURED AND
   REJECTED (with the number), or NOT REACHED. No input may be silently missing.

## Off limits

- `cost` / the price matrix — that is `cc4557feef48`'s write set.
- Any hardcoded arm exclusion. `feedback_never_hardcode_arm_exclusion`: quota, task and complexity
  decide, never a hand-kept list.
- The judge's separation of concerns (§D4) — configure its arm, do not give it quota vocabulary.
