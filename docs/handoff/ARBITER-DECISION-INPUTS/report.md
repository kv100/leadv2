# ARBITER-DECISION-INPUTS-01 — round 2 report

## Disposition

| Founder input | Status | Evidence / consequence |
| --- | --- | --- |
| D1 reset urgency | BUILT previously; untouched | `test-reset-urgency.sh` remains 10/10. |
| D2 token-size estimate | MEASURED AND REJECTED | There is no defensible pre-spawn-to-actual training set. Do not route on `expected_tokens` yet. |
| D3 finer granularity | MEASURED AND REJECTED | The recorded decision artifact omits every proposed input axis, so a replay delta cannot be calculated honestly. No new routing surface was added. |
| D4.1 GLM judge transport | BUILT | `LEADV2_JUDGE_ARM=glm|haiku`, GLM default, direct-JSON parsing, audited `judge_arm`, and one Haiku fallback are covered hermetically. The required ten-mission live comparison was not reached; see below. |
| D4.2 quota-picture advisor | NOT REACHED | Design only below. It is not wired because D2 has no valid estimate and no replay corpus can establish that advice improves routing. |

## D2 — token estimate is not derivable yet

The existing `leadv2-cost-estimate.sh` writes a phase-table forecast before
selection. It is not an observed task-token estimator. The new actuals path
does write `cost_actual` rows, but the corpus is not joinable to an estimate:

```text
cost_actual_rows=68 numeric_tokens=1 estimate_files=429 numeric_joined_to_estimate=0
numeric_task_tokens=f8880421:79015
r2=undefined reason=joined_sample_lt_2
```

This is a measured rejection, not an R-squared failure: zero paired rows makes
R² undefined. The estimator remains outside the arbiter; therefore no token
window refusal or token-fit preference was added.

## D3 — replay census and capability finding

The recorded arbiter-decision artifact had 348 rows at the census point. Its
outputs are useful (arms: fable 248, codex 66, sonnet 34), but the input fields
needed for counterfactual replay are absent:

```text
complexity_present=0/348
duration_class_present=0/348
req_eff_present=0/348
quota_present=0/348
fit_bucket_present=0/348
capability_matrix_postpick_events=0 reason=record_has_no_launch_result_or_arm_not_capable_for_kind
```

Thus claims that any refinement moves zero decisions would be fabricated; the
correct movement count is **not measurable**, not zero. No axis was refined.

The current source also falsifies the brief's post-selection capability premise:
`leadv2-route-arbiter.sh` computes `_fit` from kind/size before its later
economic sort (`ecost`). The searched `arm_not_capable_for_kind` and
`kind_unmapped=tooling` text appeared only in mission/brief artifacts, not a
recorded launcher result. A second capability matrix would duplicate a current
pre-ranking admission gate.

## D4 — judge transport and advisor design

The judge prompt remains unchanged and arm-blind. The transport now defaults to
GLM (`glm-coder.sh run`, bounded to the judge timeout and three turns) and
falls back once to Haiku. A valid result carries `judge_arm=glm` or
`judge_arm=haiku_fallback`; cached/fallback estimates remain deterministic.

The bounded live probe did not yield a valid judged result on either arm in the
available execution window, so it cannot support the required 10-mission
disagreement count. Raw probe result:

```text
--- GLM ---
{"complexity":"standard","complexity_basis":"line_count","duration_class":"medium","estimate_id":"c8bdd749","estimate_source":"fallback","estimate_v":1,"flag_source":"title","needs_live_verification":true,"risk_class":"none","subsystems_touched":4,"work_kind":"build"}
--- HAIKU ---
```

That is not evidence that GLM and Haiku agree; the live comparison is **NOT
REACHED**, and the GLM default must be re-evaluated with a completed 10+10
probe before it is treated as a demonstrated quality improvement.

Advisor design, not implementation: send one bounded cheap consultation the
sanitized window census plus a *validated* D2 estimate. Parse only
`recommended_arm` and a one-line reason; log both as advisory provenance.
Capability, protection, and all deterministic exclusions run first. The
advisor may only break an otherwise deterministic economic tie, and a timeout,
parse error, or unavailable estimate must omit the advisory token and return
the identical deterministic pick. A forced-failure proof and replay delta are
required before wiring it.

## Falsification and regression output

The judge suite's GLM-default and forced-Haiku-fallback cases passed (31/0).
The protected D1 suite passed:

```text
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
```

The required provider-price suite is absent from this pinned checkout. Its
required invocation is currently red before it can test behavior:

```text
bash: plugins/leadv2/tests/test-arbiter-prices-by-provider.sh: No such file or directory
```

This report does not restore or alter that off-limits price lane.
