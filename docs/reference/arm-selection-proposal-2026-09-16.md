# Proposal: evidence-based arm selection for leadv2

Date: 2026-09-16. Audience: the separate leadv2 implementation session.
Status: proposal only; no leadv2 application/configuration code was modified by its author.
Founder request: let GLM Flash compete for substantial suitable work, use current Opus5, preserve weekly subscription availability, and avoid unnecessarily strong models/effort. No orchestration training/bandits/automatic policy learning.

## 1. Outcome

A clear bounded bug or ordinary implementation must be able to select Flash. Expensive models must have a task-specific justification. Routing must bind model, effort, exact account, applicable quota windows and known cost provenance. A cheap request that causes repeated repairs is not a cheap delivery.

Start from the existing dispatcher and protections. Do not rebuild orchestration, reset review counters, disable caps, or roll back founder authorization for Flash's supported roles/protected paths. Apply changes in your isolated checkout, review and verify before deploying to the shared plugin.

## 2. Inputs and important corrections

Primary input: [arm-selection-logic.md](arm-selection-logic.md), supplied by the founder. Its563routes and Flash19/3.4%, GLM236/41.9% counts are attributed to that document; this session did NOT rerun the underlying journal census. Do not treat them as unbiased evidence of model success.

Read-only source checkpoint: leadv2 HEAD4f81548c44eae61b55115279d5927cd27ce85328, with potentially newer working-tree changes. The live files were inspected, not assumed identical to that commit:
- plugins/leadv2/config/leadv2-routing.yaml
- plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh

Recheck those files on implementation: the founder is actively changing them elsewhere.

### Corrections to the supplied diagnosis

1. **The flat+100 penalty is not necessarily active.** YAML capability_fit.enabled is true. Arbiter sets complexity_penalty_rules=[] when FIT_MODE is on. Source defaults therefore use fit buckets, not the old+100 penalty. An environment override can change this; inspect the effective route's fit_mode. Do not claim1000complex tasks all paid+100 from the label count alone.
2. **price_ratio is a broad losing-candidate label.** Around arbiter2099–2104, all surviving nonwinning arms receive this reason. It is not proof of a literal price-ratio admission refusal and cannot isolate economic causality from fit ordering.
3. **Insufficient capability is a demotion in this path, not automatic removal.** fit_bucket = max-like ceil(required-capability-slack), then sorting prefers lower bucket. With prior3/slack.5, standard requirement3 and Flashcap2 yieldsbucket1; cap4 yieldsbucket0. Complexrequirement4/cap2 yieldsbucket2. Other gates may still exclude an arm.
4. **Observed rounds are already consumed.** _observed_rounds uses class/arm history and multiplies ecost when enough rows exist; OBS_ON defaults enabled. Do not implement a duplicate rounds multiplier. Verify event coverage, sample selection and effective flags instead.
5. **Potential overlapping-quota defect must be checked.** In the inspected scoped Claude branch, windows.pop('seven_day', None) replaces general weekly with scoped weekly. Founder says Fable consumes BOTH. Keep both constraints; add a failing general-exhausted/scoped-available case. This is a source-level finding, not a claim that another session has not already fixed it.
6. **Model identity must be effective identity.** YAML opus is an alias. Confirm actual launched Opus5; do not infer its version from the arm label. Historical4.8 must be an explicit separately recorded choice.

## 3. Evidence and shared task matrix

The sourced research, limitations, exact observations and task/effort table are in [LEADV3-MODEL-MATRIX.md](/Users/kostiantyn.vlasenko/Projects/persona-engine/docs/LEADV3-MODEL-MATRIX.md). That document is a human-reviewed policy, not a fleet-wide success model.

Core conclusions:
- Flash deserves ordinary engineering eligibility alongside Sonnet5/Terra. Global Flash=Haiku/freepool is not supported by the checked sources.
- GLM5.3 is a candidate for uncertain integration and larger code work; do not default every standard task to it.
- Opus5 is the current default Opus choice. No evidence-backed specialty favoring4.8 was found. Keep4.8 only for reproducible regression/compatibility or task evidence and confirmed availability.
- Luna/Flash handle bounded extraction and straightforward work; higher tiers must justify incremental cost.
- Fable/Astra are available for genuinely difficult decisions, not required on every review.
- Independent review must stay independent; global strength scores are not proof that a reviewer will catch a defect.

Primary sources:
[Artificial Analysis](https://artificialanalysis.ai/leaderboards/models),
[Code Arena WebDev](https://arena.ai/leaderboard/code),
[Anthropic Opus5](https://www.anthropic.com/news/claude-opus-5),
[OpenAI models](https://developers.openai.com/api/docs/models),
[Z.ai Team Plan](https://docs.z.ai/devpack/teamplan),
[SWE-bench](https://www.swebench.com/),
[Terminal-Bench](https://www.tbench.ai/benchmarks).
Aggregators WhatLLM/BenchLM are discovery aids; source overlap is not independent evidence. LiveBench exact scores and SWE-rebench were unavailable to this reader. Model+effort+agent harness must match before comparisons.

### Task/effort policy for this handoff

| Workload | Initial candidate pool | Initial effort |
|---|---|---|
| Graph/search, extraction, short summaries | Flash, Luna, Haiku where eligible | low |
| Clear bounded bug, handler/parser, patterned refactor, focused tests | Flash, Terra, Sonnet5; GLM when justified | low/medium |
| Uncertain multi-module integration/debugging | GLM5.3, Terra, Sonnet5; escalate to Sol/Opus5/Astra | medium; high for named uncertainty |
| Routine independent review | Different adequate model/provider from author; preserve existing stronger-review rules | medium |
| Architecture or high-risk review | Opus5, Sol, Astra; Fable for specific hardest cases | high, not automatic max |
| Lead across several delivery roots | Astra, with Sol as a conditional alternative | medium; bounded high decisions |

These are task preferences, not new hard role grants. Current Opus code exclusion and any stronger-review gate require separate deliberate changes if the owner wants to alter them. Task suitability and verified availability precede cost. Same effort labels across providers do not imply equal computation or quality.

## 4. Bounded first change

### 4.1 Admission and pool membership

- Provisional ordinary-engineering capability band4: Flash, GLM, Sonnet5, Terra. This is a policy correction to coarse eligibility, NOT a derived benchmark number or a statement of equal quality.
- Keep Luna3, Haiku2 as existing coarse bands pending task-specific evidence; do not equate untrusted/freepool behavior with Flash.
- Opus5/Sol5 and Astra/Fable6 remain coarse planning/high-risk bands. Their role membership is separate.
- Preserve current founder-approved Flash kinds/sizes/trust/protected declarations. Do not introduce a permanent name-based ban on complex work. Evaluate task scope and uncertainty.
- Add/reconcile recon eligibility for Flash/Luna when those transports support read-only execution. Existing freepool/Haiku-only recon policy otherwise prevents the intended economical candidates from entering.
- Offer Sonnet/GLM/Terra/Flash in appropriate routine review pools. Stronger-only review remains mandatory where current policy requires it until its owner explicitly updates that rule. Do not silently weaken existing review gates under an economics change.
- Keep current Opus build exclusion during this bounded change; its removal is a separate product/policy decision, not needed to promote Flash. Use Opus5 in supported planning/review/audit/safety roles.
- Resolve opus to actual5. If4.8 is retained, give it an explicit versioned route and exception reason. Do not silently downgrade a failed5 launch to4.8.

### 4.2 Economics

Key cost by provider + actual model + effort + plan/account scope, not only provider. Preserve source, observed_at, sample_count, confidence and unknown status.

Separate desired attribution from what can actually be estimated. The inspected YAML records failed provider-drain fits (negative R-squared) and a prior founder decision against per-model NNLS inference from collinear shared quota meters. Do NOT reverse that by fitting the same data again or inventing model prices. Retain provider-level unknowns until identifiable observations or an applicable published plan contract exist. The current cost_src diagnostic already exposes median fallback; preserve it and add detail only where needed.

Do not replace null with invented1.0 and describe it as measured. If the algorithm needs a numeric fallback, label it a fallback policy and keep unknown prices distinguishable from equal prices. Prefer a documented task preference over fake precise economics.

Z.ai's official Team Plan currently publishes roughlyone-third Flash token credit weights. Apply those only after verifying this account uses that billing contract. Preserve cache/input/output and peak/off-peak distinctions. Do not copy API price ratios into Max/Team/Codex weekly percentages.

Existing observed rounds are a repair-cost adjustment, not success probability or token consumption. Include failed/cancelled/timed-out attempts appropriately, retain infrastructure-failure attribution, and avoid survivor/selection bias. No new automatic weight-learning loop.

### 4.3 Quotas

Admission constraints: real exhaustion, cooldown, concurrency, permissions and proven account identity.
Weekly preservation: each account's remaining allowance against its actual reset horizon; current5h controls immediate availability. Claude Fable uses general+scoped weekly simultaneously, never sum/replace. Scope-specific Codex meters constrain only applicable models.

Unknown/stale observations remain unknown. Do not let near5h reset urgency overwhelm a depleted weekly allowance. Prefer sustainable allocation among suitable routes; budget prediction is not an invented hard cap.

### 4.4 Winner consistency

In the inspected source, anti-stickiness chooses an equal-ecost alternative after sorting. Check it cannot select a worse fit bucket simply to rotate arms. Rotation should preserve eligibility, task fit and exact quota constraints. This is a targeted verification item, not a claim of a reproduced incident.

## 5. Follow-up task-specific matrix

Retire one universal capability number gradually:
- Record task category, risk, uncertainty, scope and validation strength.
- Derive admissible model/effort bands from the shared task matrix.
- Rank suitable candidates using sustainable quota, known task economics and latency requirements.
- Preserve explicit preference/rationale when measurements are unknown.
- Keep scalar capability only as compatibility metadata during migration.

Do not make a risky migration cheap by relabeling its risk. A bounded safe component can use Flash while independent architecture/review uses another adequate model.

Telemetry must distinguish not_in_pool, unsupported_role, insufficient_fit, quota_exhausted, weekly_pacing_preference, cost_unknown, higher_expected_cost, latency_preference, infrastructure_unavailable and explicit_override. A catch-all price_ratio obscures what changed.

## 6. Required acceptance cases

Use hermetic decision fixtures before live provider spend. Retain current tests and guard semantics.

1. Standard, concrete implementation: Flash admitted and can win against GLM under applicable documented cheaper-credit conditions.
2. Same task with Flash exhausted/cooling/reserved: choose an eligible alternative; no loop or forced quota bypass.
3. Complex/high-risk task: suitable strong route can win; mandatory risk/review gates remain intact.
4. FIT_MODE=on: legacy+100 absent; FIT_MODE=off behavior explicit. Report winning fit bucket and actual decisive comparator.
5. Equal ecost with different fit buckets: rotation cannot pick worse fit.
6. Null model price stays visibly unknown; known cheap is not confused with median fallback.
7. Existing observed-rounds adjustment occurs exactly once; missing samples and infrastructure errors do not invent success rates.
8. Same provider, different models/efforts: routing can distinguish them; model choice survives launcher resolution.
9. opus route actually resolves to5; explicit4.8 exception is recorded and availability checked; no silent alias downgrade.
10. Fable scoped positive/general zero and reverse both refuse; scoped exhaustion does not block unrelated Sonnet; expired readings are not fabricated headroom.
11. Near5h reset with scarce weekly quota versus another suitable account: weekly preservation still matters.
12. Same-account/profile UUID mismatch: no mislabeled quota or launch. Project defaults do not override explicitly chosen dispatcher account.
13. Direct and fallback dispatch use the same final admissibility checks and retain actual identity/effort.
14. Correct source comments and arm-selection-logic.md causal claims; historical counts retain timestamps.

Run any live calibration later on a small comparable set with frozen context/tools/tests and no forced traffic share. Include failures, repairs, elapsed time, actual quota attribution quality and reviewer defects. This is controlled evaluation, not training.

## 7. Delivery and rollback

Implement in an isolated worktree with explicit write scope. First freeze baseline decisions for the above cases, then show changed outcomes with reasons. Independent review must cover quota overlap, fallback identity, fit/rotation consistency and accidental weakening of guardrails. Do not mutate the live founder sessions to demonstrate success.

Report exact source/config commit, focused tests, actual launched model evidence if any, and remaining unknowns. Keep a reversible config revision; do not roll back unrelated live changes or founder-approved Flash permissions. This document itself authorizes no automatic rollout from the separate session beyond the founder's instructions there.
