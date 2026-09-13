# ARBITER-DECISION-INPUTS-01 — round 2: D2, D3, D4 only

Round 1 landed **D1 only** (merge `b14199d8`): `reset_urgency` in `ecost`, suite
`plugins/leadv2/scripts/tests/test-reset-urgency.sh`, 10 assertions including the (i RED)/(i GREEN)
pair that proves removing the formula flips the founder's case back to codex. It is LIVE on the
real dispatch path — a resolve-only run on 2026-09-13 emitted
`reset_claude=3.03h_live reset_urgency=claude:1.299[five_hour],codex:1.165[primary] arbiter_pick=sonnet`.

**Do not touch D1. Do not re-derive it. Do not "improve" it.** Your acceptance includes proving you
did not break it: `test-reset-urgency.sh` must stay 10/10 at the end of your work.

Also landed in the same session and equally off-limits: per-provider pricing (merge `3e89a3b8`,
`provider_cost` in `ecost`, `cost_src` provenance on every decision line, suite
`plugins/leadv2/tests/test-arbiter-prices-by-provider.sh`, 7/7). Its suite must also stay green.
Note where `ecost` now stands, because both terms live there:

```
_ru   = reset_urgency_weight(provider, arm)
_base = provider_cost(c) / ((headroom_weight or 1.0) * _ru)
```

The full round-1 mission with the founder's own words, the measured baseline, and the method
(§D5) is `docs/handoff/ARBITER-DECISION-INPUTS/MISSION.md`. **Read it first** — §D5 (search hard,
build edge cases, re-verify what seems true AND what seems false, negative control by mutating
inside the function body) binds every item below and is not repeated here.

---

## D2 — an estimate of the task's TOKEN size

Still zero matches for `token_estimate|est_tokens|expected_tokens|size_estimate` in the arbiter.
The founder named this input explicitly; today the only forecast is `forecast_hours` (p75 wall
clock), which includes an open lane's idle time and says nothing about burn.

- Start from what already exists: `docs/handoff/*/cost-estimate.yaml` is written per dispatch
  (`cost_estimate_recorded … path=…`). Read several before writing anything — the machinery may be
  half-built, and building a second one beside it is the worse outcome.
- Now that round 1's sibling lane landed real token attribution (`leadv2-turn-account-attribute.py`,
  `lib/leadv2-cost-actuals.sh`, merge `c2472b62`), there is an actuals source that did not exist
  when this was first scoped. Use it.
- Pre-spawn inputs available: mission character count (`kimi_skipped … chars=30562`), prepass write
  set size, complexity class, duration class, phase list.
- Report the fit HONESTLY. A bad estimate wired into routing is worse than none. If R² says it is
  not derivable, that number IS the deliverable — the pricing lane's honest negative (5h kept=99
  R²=−0.3152, max_abs_corr=1.000, degenerate_pairs=7) is what let the founder decide correctly.
- If derivable: compare it against window REMAINDERS the way the hours-forecast already does, so
  "does this task fit in what is left" is answerable in tokens.

## D3 — granularity, made concrete

Census first, change second. For each axis the decision currently collapses, answer with evidence
whether a finer value moves any recorded routing decision:
- `complexity` — 3 buckets; `duration_class` — short/medium/long; `req_eff` — one float;
  quota — per provider, fable the only sub-bucket; `fit_bucket` ties (`sonnet:0,codex:0,codex:0`).
- **Measured today, add it to the census:** the arbiter picked sonnet and the launcher then refused
  it — `refused: arm_not_capable_for_kind` — and the lane fell back to codex. A second resolve-only
  run emitted `kind_unmapped=tooling`. So capability under `--kind` is checked AFTER the arm is
  chosen, not as part of choosing. Count how often that happens across the recorded decisions and
  decide whether `kind` belongs in the capability matrix the arbiter reads.

An axis whose refinement moves ZERO decisions is reported as moving zero and left alone — that is
the acceptance, not a disappointment. Refine only where the replay shows movement, and give the count.

## D4 — the services must be smart, and must talk

1. The judge runs on haiku (`leadv2-task-judge.sh:60`, `JUDGE_MODEL="${LEADV2_JUDGE_MODEL:-haiku}"`):
   the decision layer spends Anthropic quota to decide how to spend Anthropic quota, while the
   founder has offered the GLM key for exactly this. Make the arm configurable, default it to GLM,
   keep haiku as fallback. Prove it: run both arms over a fixed set of ≥10 real missions and report
   the disagreement count. If GLM disagrees materially, keep haiku and say so — a cheaper judge
   that is worse is not a win.
2. Design a quota-picture advisor: given the full window census plus the D2 estimate, one cheap LLM
   call returns a recommendation and a one-line reason, logged, treated as ONE input among the
   deterministic terms. It must never override capability or protection, and the deterministic path
   must produce the SAME answer when the call fails or times out — prove that by forcing a failure.
   Say plainly whether you built it or only designed it.

Keep the judge→arbiter boundary intact: the judge carries zero arm/model/provider/quota vocabulary
(`leadv2-task-judge.sh:11`). Configure its arm; do not give it quota vocabulary.

Standing: `feedback_decision_layer_may_spend_to_decide_well` — spending to decide well is approved.
Cost is not a reason to skip an LLM call here; being unable to prove it helps is.

---

## Acceptance

1. `test-reset-urgency.sh` 10/10 and `test-arbiter-prices-by-provider.sh` 7/7 at the end — you did
   not break what round 1 landed.
2. Replay over the recorded routing decisions: per item, how many decisions changed and which.
   Zero is a reportable result, not a failure to hide.
3. Every new suite registered so `tests/run-all.sh --scope changed` SELECTS it. Commit first, then
   show the selection output — `git diff --name-only origin/main...HEAD` drives selection and does
   not see uncommitted work.
4. Per founder input, state exactly one of: BUILT (with the replay delta), MEASURED AND REJECTED
   (with the number), NOT REACHED. Nothing may be silently missing.
5. Put new suites in `plugins/leadv2/scripts/tests/` (547 suites) unless you can say why
   `plugins/leadv2/tests/` (57 suites) is the right root for yours.

## Off limits

- `reset_urgency` and `provider_cost` — landed, suite-proven, not yours to revise.
- Any hardcoded arm exclusion (`feedback_never_hardcode_arm_exclusion`).
- `docs/leadv2/open-threads.md` and `docs/tasks.yaml` — lead-owned.
