# HOW-DO-WE-EVER-GET-A-PRICE-01 — diagnosis and measurement design

## Decision

**Do not fit a price from the current observational shape.** The Codex one-column
fit has `max_abs_corr=0.000` and `degenerate_pairs=0`, but its fitted
lane-token signal accounts for only **27.219 of 95.000 observed percentage
points (28.7%)**. The signed residual is **67.781 points (71.3%)** and the
absolute residual is **100.375 points (105.7%)**. These are in-sample
diagnostics, not an attribution of the residual to a named user.

The independently measured primary cause is **time misassignment**: the fitter
assigns a task's cumulative tokens to the interval containing its final spawn,
not the time it actually ran. **65/123 (52.8%)** usable Codex jobs completed
after that assigned quota interval ended. Account pollution, unretained/missing
token evidence, percentage quantisation, and omitted fixed request overhead
are additional unseparated contributors. The current data cannot identify their
individual shares; calling all 71.3% “other users” would be unsupported.

**Verdict:** no observational fit over this target/predictor shape can yield a
defensible provider price. It becomes admissible only with provider-unit
accounting/published weights or an exclusive controlled experiment. The 7-day
coefficient is not admissible: its target spans seven days but its
`turn_events` predictors retain only 48 hours.

## Fit record

| Surface/shape | kept | R2 | max_abs_corr | degenerate_pairs | Verdict |
| --- | ---: | ---: | ---: | ---: | --- |
| drain weights, 5h/provider | 112 | -0.2988 | 0.670 | 0 | reject |
| drain weights, 7d/provider | 76 | -0.6072 | 0.659 | 0 | reject: 48h retention |
| Codex drain, provider | 114 | -0.3974 | 0.000 | 0 | decisive non-degenerate reject |
| Codex drain, per-model | 61 | 0.1456 | 0.402 | 0 | directional only, not price |

The first two rows are recorded in
`docs/handoff/2bbf42c25145/MISSION.md:27-33`; the Codex rows are in
`docs/handoff/dispatch-c8711201/report.md:56-63`. No value is inferred from
any of them.

## Measured cause

`leadv2-codex-drain-fit.py` uses all journal `util_codex` readings as the
shared account target and assigns a lane total to the final registered spawn
(`plugins/leadv2/scripts/leadv2-codex-drain-fit.py:10-43, 297-362`). The
following direct reconstruction uses its grouping and NNLS solver with each
matching rollout's final `thread_token_usage`; it prints no token totals,
handles, thread IDs, or account IDs.

```text
direct_rollout_reconstruction tasks=242 token_resolved=119 token_unresolved=123 readings=332 kept=114 reset=2 idle=215
fit group=provider kept=114 r2=-0.3974 max_abs_corr=0.000 degenerate_pairs=0
target_sum_pct=95.000 fitted_sum_pct=27.219 fitted_share=28.7% signed_residual_pct=67.781 absolute_residual_pct=100.375 mae_pct=0.880 mean_target_pct=0.833
```

The fitted 28.7% is an upper-bound diagnostic within a contaminated,
mis-timed target, not physical attribution. Timing independently shows why:

```text
codex_timing source=arm-registered+job-json readings=332 handles=334 usable=123 unresolved=18 launch_outside=193
task_duration_minutes min=0.4 p50=14.0 p90=38.2 p95=54.4 max=181.7
assigned_interval_minutes min=0.2 p50=10.4 p90=213.4 p95=539.5 max=718.2
completed_after_assigned_interval=65/123=52.8% crosses_interval_boundary=65/123=52.8%
```

`launch_outside=193` is a coverage warning, not a claim those launches cost
zero. The code explicitly drops reset intervals, exact zero-delta/zero-token
idle intervals, and Fable intervals with an unmodelled scoped meter
(`leadv2-drain-weights.py:259-283`). Thus idle filtering does not remove a
positive observed target. It only says reads are denser than eligible work.
The seven-day shape remains invalid because
`RETENTION_LIMIT_H = 48` (`leadv2-drain-weights.py:72-73, 301-306`);
76 rows cannot restore six-plus days of missing predictor mass.

## Published-weight search

**Finding: no authoritative Codex or Claude *subscription* relative-weight
table was found.** This is not a finding of zero price.

| Surface | Live check | Establishes | Price verdict |
| --- | --- | --- | --- |
| Local quota reader | Active Anthropic: 5h=10%, 7d=16%, one scoped window | account-level percent windows only | not per-request units |
| Installed CLI | Claude 2.1.270; Codex CLI 0.153.4; Codex help lists login/logout, no usage command | no local Codex accounting surface | not a weight |
| [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing) | HTTP 200; token/cache fields present | API request accounting | API billing is not Claude Code quota |
| [Anthropic organization usage report](https://platform.claude.com/docs/en/api/beta/organization/usage_report/retrieve_messages) | HTTP 200; model-filtered usage fields present | Admin API can audit model API use | not subscription quota |
| [OpenAI Codex plan usage](https://help.openai.com/en/articles/11369540) and [Astra usage](https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex) | curl HTTP 403 for both | URLs recorded; contents not readable in this lane | **UNVERIFIED:** no weight derived |
| [Z.AI team plan](https://docs.z.ai/devpack/teamplan.md) | HTTP 200; credit formula and GLM 6.9/24 vs Flash 2.3/8 multipliers visible | published provider units | supports existing 0.33 only |

```text
anthropic_probe accounts=3
account status=unknown active=False five_hour_pct=None seven_day_pct=None scoped_windows=0
account status=ok active=False five_hour_pct=6.0 seven_day_pct=83.0 scoped_windows=1
account status=ok active=True five_hour_pct=10.0 seven_day_pct=16.0 scoped_windows=1
ANTHROPIC_PROBE_RC=0
openai_codex_plan status=403 url=https://help.openai.com/en/articles/11369540
openai_astra_usage status=403 url=https://help.openai.com/en/articles/20001516-managing-usage-with-gpt-6-astra-in-work-and-codex
anthropic_pricing status=200 url=https://platform.claude.com/docs/en/about-claude/pricing
anthropic_usage_report status=200 url=https://platform.claude.com/docs/en/api/beta/organization/usage_report/retrieve_messages
zai_teamplan status=200 url=https://docs.z.ai/devpack/teamplan.md
```

## Designed path to a price

### Preferred: published provider units

1. Capture an official subscription/CLI surface that states model weighted
   units or credits per request, with URL, retrieval date, response shape, and
   fresh quota read.
2. Define `weighted_tokens = input*w_in + cached*w_cache + output*w_out +
   tool_units*w_tool` exactly as published. Fit one provider scale, then
   validate it on six held-out exclusive batches.
3. Report mean quota-delta per weighted token and a 95% interval; accept only
   if the interval is narrower than the routing-order separation margin.

This is cheap in quota terms and retains per-model resolution. Its failure mode
is plan/endpoint drift, so bind the value to plan and retrieval date and
invalidate on drift. It exists for GLM; this search did not find it for Codex
or Claude subscriptions.

### Fallback: exclusive controlled step response

1. Reserve an account/provider/window. Read quota twice separated by the
   local reader TTL (Codex 120s, Anthropic 300s:
   `leadv2-quota-read.py:91-96`). Proceed only if values and account identity
   are stable; freeze founder use, lanes, and background tools.
2. Send one fixed, versioned workload per model and record complete reported
   usage (input, cached input, output, reasoning/tool units). Read immediately
   after and after the observed propagation delay. Any reset, unknown, or
   account movement invalidates the batch.
3. Extend a batch until its quota movement is at least **5 percentage points**,
   then collect **six independent batches per model**. The live surface is
   displayed in whole percentage points, so a before/after difference has up
   to one point of rounding uncertainty: 20% worst case at a five-point batch.
4. Estimate `q=Δpct/effective_token` and publish a 95% interval via an
   interval-censored bootstrap: resample the six batches while sampling each
   displayed delta within `[Δ-1, Δ+1]`. If the interval is too broad, report
   *resolution insufficient*, not a rounded price.

Minimum quota cost is **30 displayed percentage points per model**: at least
90 for three Codex models and 120 for haiku/sonnet/opus/Fable, with Fable's
scoped meter calibrated separately. This is a lower bound: the token/request
quantity required to move five points is the unknown under test. It may span
multiple reset windows.

If that experiment finds per-model differences without published weights, do
not write one invented provider scalar. Keep a workload-mixture-specific value
with its interval, or separately redesign the schema.

## Pre-write landmine

No routing price changed. Before any future write, resolve
`PRICE-KEY-ANTHROPIC-VS-CLAUDE-MISMATCH-01`: YAML keys `anthropic`, while
both price-key implementations return the matrix provider `claude`
(`leadv2-routing.yaml:179,314-331`,
`leadv2-launch-registry.py:277-278`,
`leadv2-route-arbiter.sh:581-582`). A price written today would silently
fall back to the median.

## Falsification and regression evidence

The first direct SQLite query was denied by the sandbox. The report therefore
uses durable rollout/journal data for the residual measurement and does not
modify the burn writer.

```text
Error: in prepare, unable to open database file (14)
SQLITE_RC=14
```

This is report-only: no shell or Python source changed, so `bash -n` and
`py_compile` have no changed files. Focused suite and changed-scope output is
appended after foreground execution.


### Required focused suites - raw terminal result

The first price-suite attempt was red because this sandbox refuses the system
temporary directory. The suite wrote its fixture paths as /live.sh etc. after
mktemp -d failed; no repository source was involved. Re-running the unchanged
suite with an exported in-memory mktemp function targeting /private/tmp was
green:

~~~text
RED:
mktemp: mkdtemp failed on /var/folders/.../tmp...: Operation not permitted
FAIL: (1) ... routing_yaml_unreadable detail=path='/r1.yaml'
SUMMARY pass=0 fail=7

GREEN:
PASS: (1) cheaper provider (glm 1.0 < codex 5.0) wins, cost_src=glm:measured
PASS: (2) negative control: prices swapped -> arm=codex wins
PASS: (3) null price -> arm still selected, cost_src=glm:median
PASS: (4) cost: block absent -> legacy row cost honoured
PASS: (5) max_cost=2 excludes codex
PASS: (5b) same max_cost against swapped prices -> exclusion flips
PASS: (6) malformed router_v2.cost.codex -> rc=2, reason=routing_yaml_invalid
SUMMARY pass=7 fail=0
~~~

~~~text
plugins/leadv2/scripts/tests/test-codex-drain-fit.sh
SUMMARY pass=13 fail=0
plugins/leadv2/scripts/tests/test-codex-lane-token-total.sh
SUMMARY pass=9 fail=0
plugins/leadv2/scripts/tests/test-reset-urgency.sh
SUMMARY: pass=10 fail=0
plugins/leadv2/scripts/tests/test-arbiter-decision-record-inputs.sh
SUMMARY pass=6 fail=0
plugins/leadv2/scripts/tests/test-launcher-refusal-event.sh
launcher-refusal-event: PASS=4 FAIL=0
plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh
=== Results: 36 passed, 0 failed ===
~~~

No shell or Python source changed. The requested syntax set is therefore
empty; git diff --check is the applicable static green check.

### Changed-scope runner - raw terminal result

~~~text
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 0 of 93 suites (base=main@082e556b4f, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=93 base=main@082e556b4f changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/2bbf42c25145
[PASS] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] .../tests/test-status-surface-bash32.sh
CHANGED_SCOPE_RC=124
~~~

The report-only diff selected no relevant plugin suite, then the repository
runner hung in its unconditional status-surface suite and was stopped at the
explicit 20-second bound. It is not claimed green; the seven required focused
suites above are green.
