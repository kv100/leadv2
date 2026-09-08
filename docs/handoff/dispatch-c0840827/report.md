# P1b — launch what the arbiter chose

Implementation and focused verification are complete. Live non-sonnet launch proof passed. Closure is blocked: the changed-scope runner timed out at 900 seconds, and the live work-slot usage response is now HTTP 200, so the requested live HTTP-401 auction cannot be claimed. The 401 auction is proven with an explicitly labelled fixture below.

The lane started clean at `2780cf07`. Changes are confined to the dispatcher, arbiter, three registered suites and this handoff. The launch registry and codex-task.sh are unchanged.

## Implementation evidence

- The launchability seam imports the existing Python registry for Claude/Codex. GLM/freepool keep their existing adapters. The registry narrows capability; fable/code is still refused. A Claude registry miss returns the existing arm-refused result before invoking the subsession binary.
- Claude worker arms share the registry-derived argv path, the requested profile, and the arbiter's effort. Liveness retains the actual worker PID for all four Claude arms. The launcher emits `launch_model_resolved` from the argv it resolved.
- The pre-arbiter opus park is removed. The existing common reserve/spawn/confirm transaction handles its reservation and duplicate protection. The old reserve-only helper is retained; no registry or pool-default data was duplicated.
- The arbiter consumes the producer's `account_state`. `unmetered` has penalty 0 and uses configured matrix cost divided by the least generous configured headroom weight (0.2 in this configuration); it is never represented as measured usage. `unknown` retains penalty 50. This is conservative configured pricing, not an estimate of remaining account tokens. The existing headroom-gradient disable switch still disables headroom scaling.

## Preconditions evidence

```text
$ git branch --merged main | grep worktree-13581c3eb064
+ worktree-13581c3eb064
$ git merge-base --is-ancestor 4e15098b HEAD
RC=0
$ git diff 2780cf07 HEAD -- plugins/leadv2/scripts/lib/leadv2-launch-registry.py plugins/leadv2/scripts/codex-task.sh
```

Graph discovery returned “MCP tool call requires approval, but approval policy is never”; inspection used local source reads afterward.

## Live dispatch evidence — model_select_telemetry and launch_model_resolved

The real dispatcher and real claude-subsession.sh ran in a temporary git root with `--kind recon --pin-arm haiku --requested-profile work`. Placement/bookkeeping and the classifier were isolated fixtures; Claude quota was the captured live reader response. GLM/Codex quota was explicitly unknown. The actual Claude process completed before this session continued. This proves the decision-to-launch model binding, not all production lifecycle gates.

Invocation: `TMPDIR=/tmp timeout 180 bash /tmp/p1b-live-probe.sh`. The exact probe is preserved as [live-probe.sh](live-probe.sh); its recorded quota input came from `LEADV2_QUOTA_CACHE_DIR=/tmp/p1b-live-quota timeout 70 python3 plugins/leadv2/scripts/leadv2-quota-read.py anthropic --no-cache`.

```text
[leadv2-dispatch-code] launch_model_resolved task=4c7a541c task_id=dispatch-4c7a541c arm=haiku resolved_model=haiku
[leadv2-dispatch-code] model_select_telemetry task=4c7a541c role=worker class=light work_kind=recon arm=haiku model=haiku fallback_depth=0 floor=none spawn_to_terminal_s=11 terminal=win cause=worker_spawned
LIVE_DISPATCH_RC=0
PROBE_RC=0
```

The real Claude result reports `P1B_LIVE_OK`, completed with no error, using haiku. Raw provider result artifact:

```text
{"duration_api_ms":2760,"stop_reason":"end_turn","session_id":"bfafc495-ffc8-49c4-b1fb-b4f33b3b0d44","total_cost_usd":0.0539943,"usage":{"input_tokens":10,"cache_creation_input_tokens":25919,"cache_read_input_tokens":13963,"output_tokens":150,"output_tokens_details":{"thinking_tokens":136},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":25919,"ephemeral_5m_input_tokens":0},"inference_geo":"not_available","iterations":[{"input_tokens":10,"output_tokens":150,"cache_read_input_tokens":13963,"cache_creation_input_tokens":25919,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":25919},"type":"message"}],"speed":"standard"},"modelUsage":{"claude-haiku-4-5-20251001":{"inputTokens":10,"outputTokens":150,"cacheReadInputTokens":13963,"cacheCreationInputTokens":25919,"webSearchRequests":0,"costUSD":0.0539943,"contextWindow":200000,"maxOutputTokens":32000,"thinkingTokens":136,"canonicalModel":"claude-haiku-4-5","provider":"firstParty","costBasis":"list"}},"permission_denials":[],"terminal_reason":"completed","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required","subagent_stats":{"spawned":0,"requested":{"background":0,"foreground":0,"unset":0},"started_in_background":0,"max_depth":0,"spawned_by_subagents":0,"completed":0,"failed":0,"killed":{"parent":0,"user":0,"system":0},"refused":{"depth_limit":0,"concurrency_limit":0,"budget":0},"by_type":{}},"is_error":false,"num_turns":1,"subtype":"success","api_error_status":null,"result":"P1B_LIVE_OK","ttft_ms":3395,"type":"result","duration_ms":4078,"uuid":"b8cb282d-370a-49ad-bb98-21abc9472ea1","ttft_stream_ms":1873,"time_to_request_ms":720,"first_content_frame_ms":2207,"queued_turn_count":0}
```

Full invocation output: [live-dispatch-final.log](live-dispatch-final.log).

## Live usage and HTTP-401 fixture auction evidence

The live work-slot reader returned HTTP 200; the personal-slot entries returned 429 and 200. This is the live check output (slot labels only):

```text
{"status": "ok", "accounts": [{"slot": "personal", "http": 429, "status": "unknown", "account_state": "unknown", "subscription_type": "max", "five_hour_pct": null, "seven_day_pct": null}, {"slot": "work", "http": 200, "status": "ok", "account_state": "ok", "subscription_type": "team", "five_hour_pct": 39.0, "seven_day_pct": 26.0}, {"slot": "personal", "http": 200, "status": "ok", "account_state": "ok", "subscription_type": "max", "five_hour_pct": 3.0, "seven_day_pct": 53.0}]}
```

UNVERIFIED: a live work-slot HTTP-401 auction. No live HTTP-401 response was fabricated. The following is a fixture dispatch with `account_state=unmetered`, team/401, an explicit sonnet/codex pool, and no spawn. The production dispatcher emits the winning route and penalty:

```text
FIXTURE_QUOTA={"anthropic":{"status":"unknown","accounts":[{"account_label":"work","active":true,"status":"unknown","account_state":"unmetered","subscription_type":"team","http":401}]},"codex":{"status":"unknown"},"glm":{"status":"unknown"}}
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=sonnet model=sonnet tier=standard effort=low task=188b0644 reason=cheapest_capable arbiter_pick=sonnet util_glm=unknown_capped util_codex=unknown_capped util_claude=unmetered util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=0.2 claude_account_state=unmetered claude_probe_penalty=0 claude_priced_from=configured_allowance_conservative arm_excluded=codex:price_ratio,glm:not_in_pool arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=complex duration_class=unknown complexity_policy=capability_fit remaining=unmetered reset_in=n/a reset_basis=n/a probe_outage=glm,codex failure_memory=no_history complexity_source=judge conf=0.9 req_eff=4.0 fit_mode=on fit_pick=sonnet fit_differs=0 fit_bucket=sonnet:0,codex:0
FIXTURE_DISPATCH_RC=0
```

Full fixture output: [unmetered-dispatch-fixture.log](unmetered-dispatch-fixture.log). The account suite below additionally obtains its state from the real producer's `classify_account_state` and checks both zero and 50 penalties.

## bash -n and python3 -m py_compile evidence

```text
$ timeout 10 bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh
RC=0
$ timeout 10 bash -n plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh
RC=0
$ timeout 10 bash -n plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh
RC=0
$ timeout 10 bash -n plugins/leadv2/tests/test-unmetered-account-not-penalised.sh
RC=0
$ timeout 10 bash -n plugins/leadv2/tests/test-arm-pool-reachability.sh
RC=0
$ timeout 10 bash -n docs/handoff/dispatch-c0840827/live-probe.sh
RC=0
python3 -m py_compile: no Python files changed
```

## LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh evidence

`LEADV2_RUN_ALL_LIST_TRIGGERS=1 timeout 20 bash tests/run-all.sh` selected all three suites through their self-registration declarations; tests/run-all.sh was not edited. Matching raw rows follow; the complete listing is in [trigger-registration.log](trigger-registration.log).

```text
leadv2-dispatch-code:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-route-arbiter:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-routing.yaml:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-glm-policy-resolve.py:plugins/leadv2/tests/test-arm-pool-reachability.sh
leadv2-dispatch-code:plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh
leadv2-route-arbiter:plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh
leadv2-dispatch-code:plugins/leadv2/tests/test-unmetered-account-not-penalised.sh
leadv2-route-arbiter:plugins/leadv2/tests/test-unmetered-account-not-penalised.sh
```

## test-launch-uses-the-chosen-arm.sh green evidence

`TMPDIR=/tmp timeout 60 bash plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh`

```text
decision launch_model_resolved task=argv-sonnet task_id=dispatch-argv-sonnet arm=sonnet resolved_model=sonnet
decision worker_spawned by=router model=sonnet task=argv-sonnet attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
worker_spawned model=sonnet task=argv-sonnet attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
decision mission-version task=- sig=argv-sonnet rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
SUBSESSION_ARGV arm=sonnet argv=['--role', 'developer', '--model', 'sonnet', '--effort', 'high', '--task-id', 'dispatch-argv-sonnet', '--mission-file', '/tmp/leadv2-dispatch-mission.OhabEq', '--requested-profile', 'work']
decision launch_model_resolved task=argv-haiku task_id=dispatch-argv-haiku arm=haiku resolved_model=haiku
decision worker_spawned by=router model=haiku task=argv-haiku attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
worker_spawned model=haiku task=argv-haiku attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
decision mission-version task=- sig=argv-haiku rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
SUBSESSION_ARGV arm=haiku argv=['--role', 'developer', '--model', 'haiku', '--effort', 'high', '--task-id', 'dispatch-argv-haiku', '--mission-file', '/tmp/leadv2-dispatch-mission.yhBlAs', '--requested-profile', 'work']
decision launch_model_resolved task=argv-fable task_id=dispatch-argv-fable arm=fable resolved_model=fable
decision worker_spawned by=router model=fable task=argv-fable attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
worker_spawned model=fable task=argv-fable attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
decision mission-version task=- sig=argv-fable rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
SUBSESSION_ARGV arm=fable argv=['--role', 'developer', '--model', 'fable', '--effort', 'high', '--task-id', 'dispatch-argv-fable', '--mission-file', '/tmp/leadv2-dispatch-mission.fnGNMg', '--requested-profile', 'work']
decision launch_model_resolved task=argv-opus task_id=dispatch-argv-opus arm=opus resolved_model=opus
decision worker_spawned by=router model=opus task=argv-opus attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
worker_spawned model=opus task=argv-opus attempt=fixture handle=PID=66609 LABEL=fixture SESSION_ID=fixture
decision mission-version task=- sig=argv-opus rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
SUBSESSION_ARGV arm=opus argv=['--role', 'developer', '--model', 'opus', '--effort', 'high', '--task-id', 'dispatch-argv-opus', '--mission-file', '/tmp/leadv2-dispatch-mission.YTVV1b', '--requested-profile', 'work']
decision arm_refused by=router model=fable task=incapable reason=launch_registry_miss detail=refused:_not_a_build_arm_
PASS registry miss refuses before subsession; all four actual argv models match
```

## test-unmetered-account-not-penalised.sh green evidence

`TMPDIR=/tmp timeout 60 bash plugins/leadv2/tests/test-unmetered-account-not-penalised.sh`

```text
arm=sonnet kind=docs model=sonnet tier=standard effort=low reason=capability_fit chain=sonnet,codex,haiku util_glm=unknown_capped util_codex=unknown_capped util_claude=unmetered util_freepool=100 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=0.2 claude_account_state=unmetered claude_probe_penalty=0 claude_priced_from=configured_allowance_conservative arm_excluded=codex:price_ratio,freepool:not_in_pool+not_launchable,glm:not_in_pool+not_launchable,glm-flash:not_in_pool+not_launchable,haiku:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unmetered reset_in=n/a reset_basis=n/a probe_outage=glm,codex failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=sonnet fit_differs=1 fit_bucket=sonnet:0,codex:0,codex:0,haiku:1
PENALTY state=unmetered actual=0 expected=0
arm=codex kind=docs model=gpt-6-astra tier=volume effort=low reason=capability_fit chain=codex,sonnet,haiku util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=100 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:not_in_pool+not_launchable,glm:not_in_pool+not_launchable,glm-flash:not_in_pool+not_launchable,haiku:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,haiku:1
PENALTY state=unknown actual=50 expected=50
arm=sonnet kind=docs model=sonnet tier=standard effort=low reason=capability_fit chain=sonnet,codex,haiku util_glm=unknown_capped util_codex=unknown_capped util_claude=20 util_freepool=100 reset_glm=n/a reset_codex=n/a reset_claude=5.00h_default_full_period reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=ok claude_probe_penalty=0 claude_priced_from=measured arm_excluded=codex:price_ratio,freepool:not_in_pool+not_launchable,glm:not_in_pool+not_launchable,glm-flash:not_in_pool+not_launchable,haiku:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=80.0 reset_in=5.00h reset_basis=default_full_period probe_outage=glm,codex failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=sonnet fit_differs=1 fit_bucket=sonnet:0,codex:0,codex:0,haiku:1
PENALTY state=ok actual=0 expected=0
PASS unmetered penalty=0; unknown penalty=50; measured penalty=0
```

## test-arm-pool-reachability.sh green evidence

`TMPDIR=/tmp timeout 300 bash plugins/leadv2/tests/test-arm-pool-reachability.sh`

```text
PASS: bash syntax: dispatch
PASS: (g1) pin fable plan/heavy resolves as fable
PASS: (g1) the dispatcher selects fable
PASS: (g1) requested_arm_incapable is gone for a capable (matrix-covered) arm
PASS: (g1) the launchability seam names its source (registry)
PASS: (g1) capable pin resolves (rc=0)
PASS: (g2) --pin-arm behaves exactly like --requested-arm (selection + persisted pin)
PASS: (g3) pin sonnet with claude at 99% refuses: requested_arm_capped
PASS: (g3) the capped stage is typed on the line (sonnet:capped)
PASS: (g3) capped pin exits 4 (rc=4)
PASS: (g4) explicit pool glm,codex: winner (glm) runs inside the set
PASS: (g4) arms outside the hard set are typed not_in_pool (sonnet)
PASS: (g4) explicit pool resolves, rc=0 (rc=0)
PASS: (g5) unknown pool member refused at the door, before any resolution
PASS: (g6) pin+pool conflict refused (a pin IS a singleton pool)
PASS: (g7) fable cannot launch code and is refused
PASS: explicit --pin-arm opus reached spawn with model opus
PASS: (m1) chain-as-pool regression reproduces: pin dies as not_in_pool, suite is red under it
PASS: (m3) stripped exit lets the capped pin continue (rc=0), suite is red under it
---
SUMMARY: pass=19 fail=0

SUITE_RC=0
```

## leadv2-mutation-control.sh evidence — red controls

All mutations are inside production function bodies and leave the production worktree untouched. Commands use `TMPDIR=/tmp LEADV2_LANE_START_SHA=2780cf07 timeout 180 bash plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <target> <patch> docs/handoff/dispatch-c0840827`. For the opus control, `P1B_POOL_CASE=opus` selects the same opus case from the fully registered pool suite. Final artifacts will be rerun after this report is committed and stored under `mutation-control/final/`, excluded from the lane identity hash by the repository's own tool.

### Launch argv control

Suite: `test-launch-uses-the-chosen-arm.sh`; target: `leadv2-dispatch-code.sh`; patch: [launch.patch](launch.patch). Restore literal `--model sonnet` at the subsession invocation, preserving effort. The subsession recorder, not the decision journal, sees the wrong model:

```text
patching file 'plugins/leadv2/scripts/leadv2-dispatch-code.sh'
decision launch_model_resolved task=argv-sonnet task_id=dispatch-argv-sonnet arm=sonnet resolved_model=sonnet
decision worker_spawned by=router model=sonnet task=argv-sonnet attempt=fixture handle=PID=56634 LABEL=fixture SESSION_ID=fixture
worker_spawned model=sonnet task=argv-sonnet attempt=fixture handle=PID=56634 LABEL=fixture SESSION_ID=fixture
decision mission-version task=- sig=argv-sonnet rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
SUBSESSION_ARGV arm=sonnet argv=['--role', 'developer', '--model', 'sonnet', '--effort', 'high', '--task-id', 'dispatch-argv-sonnet', '--mission-file', '/tmp/leadv2-dispatch-mission.SHBzHm', '--requested-profile', 'work']
decision launch_model_resolved task=argv-haiku task_id=dispatch-argv-haiku arm=haiku resolved_model=haiku
decision worker_spawned by=router model=haiku task=argv-haiku attempt=fixture handle=PID=56634 LABEL=fixture SESSION_ID=fixture
worker_spawned model=haiku task=argv-haiku attempt=fixture handle=PID=56634 LABEL=fixture SESSION_ID=fixture
decision mission-version task=- sig=argv-haiku rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
SUBSESSION_ARGV arm=haiku argv=['--role', 'developer', '--model', 'sonnet', '--effort', 'high', '--task-id', 'dispatch-argv-haiku', '--mission-file', '/tmp/leadv2-dispatch-mission.6q2hOn', '--requested-profile', 'work']
Traceback (most recent call last):
  File "<stdin>", line 5, in <module>
AssertionError: ARGV_MISMATCH expected=haiku actual=sonnet

SUITE_RC=1
```

```text
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=0
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=AssertionError: ARGV_MISMATCH expected=haiku actual=sonnet diff_hash=1c775b294d65cae9db05a7d4c7e8f2831aee5d3cbe4630a69a9a4b0fc72c8d5c lane_diff_hash=2cbfd7adbb857bbbaada4ab9861a5a9aa8a079d778e3afe193d24b98a6195a73

MUTATION_TOOL_RC=0
```

### Unmetered penalty control

Suite: `test-unmetered-account-not-penalised.sh`; target: `lib/leadv2-route-arbiter.sh`; patch: [unmetered.patch](unmetered.patch). Map unmetered back to unknown inside the consumer:

```text
patching file 'plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh'
arm=codex kind=docs model=gpt-6-astra tier=volume effort=low reason=capability_fit chain=codex,sonnet,haiku util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=100 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:not_in_pool+not_launchable,glm:not_in_pool+not_launchable,glm-flash:not_in_pool+not_launchable,haiku:price_ratio,sonnet:price_ratio arb_rev=06abe33c7c4a matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,haiku:1
PENALTY state=unmetered actual=50 expected=0
Traceback (most recent call last):
  File "<stdin>", line 6, in <module>
AssertionError: PENALTY_MISMATCH usable account charged 50

SUITE_RC=1
```

```text
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=1
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-unmetered-account-not-penalised.sh file=plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh red_line=arm=codex kind=docs model=gpt-6-astra tier=volume effort=low reason=capability_fit chain=codex,sonnet,haiku util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=100 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:not_in_pool+not_launchable,glm:not_in_pool+not_launchable,glm-flash:not_in_pool+not_launchable,haiku:price_ratio,sonnet:price_ratio arb_rev=06abe33c7c4a matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,haiku:1 diff_hash=0d6e014df5b2a205cc9804288936c2fccb469ae134101822ebbbc95e7e2c6699 lane_diff_hash=4d7c66fc6366b8a12072e8fcf2e68911049481cb709db1b3c41c4c09f297e972

MUTATION_TOOL_RC=0
```

### Opus park control

Suite: `test-arm-pool-reachability.sh`; target: `leadv2-dispatch-code.sh`; patch: [opus-park.patch](opus-park.patch). Restore the unconditional pre-arbiter park. The first control survived because the legacy resolver returned glm before the arbiter selected opus. That result is preserved in [opus-park-mutation.log](opus-park-mutation.log), and is not counted as a killed mutation. The corrected case supplies a legacy resolver fixture returning opus and asserts that the pre-arbiter site saw opus; the real registry, arbiter and subsession-argv recorder remain in the path. Positive and negative raw results:

```text
PASS: bash syntax: dispatch
PASS: explicit --pin-arm opus reached spawn with model opus
SUMMARY: pass=2 fail=0
```

```text
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=1
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-arm-pool-reachability.sh file=plugins/leadv2/scripts/leadv2-dispatch-code.sh red_line=FAIL: explicit --pin-arm opus failed to reach spawn -- rc=3  [leadv2-dispatch-code] arm_pool_persisted task=2dfa5b60 pool=- pin=opus src=cli diff_hash=967bacdcf969e394e43857dc60c6dbc7b88b807bb2345512acecc7ca5b1ed375 lane_diff_hash=e753057c8e55359b1aec374ed1210bd99884e5fd75ecc07757b1e66ba2b0636a

MUTATION_TOOL_RC=0
```

## tests/run-all.sh --scope changed evidence

`TMPDIR=/tmp timeout 900 bash tests/run-all.sh --scope changed`

```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/da195ecf5abc/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh

CHANGED_SCOPE_RC=124
```

This check is not green. The wrapper selected 119 suites; its core runner reported 116 selected with five changed files and zero unmapped files. It did not complete before the bound. The runner's timeout cleanup removed its shard logs; these rows were captured by tool reads before cleanup:

```text
Observed via tool reads while the runner was active; its timeout cleanup removed the shard logs.
[CORE-OFFLINE] scope=changed running 116 of 95 suites (base=main@0424a4516a, 5 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=116 total=95 base=main@0424a4516a changed=5 unmapped=0 reason=-
[CORE-OFFLINE] running 116 suites across 4 shards
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-effort-routing.sh (scope-selected ad-hoc)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh (scope-selected ad-hoc)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh (scope-selected ad-hoc)
```

The unchanged effort suite independently reproduces an environment failure before reaching its assertions:

```text
$ git diff 2780cf07 HEAD -- plugins/leadv2/scripts/tests/test-effort-routing.sh
$ TMPDIR=/tmp timeout 10 bash plugins/leadv2/scripts/tests/test-effort-routing.sh
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.5KZc7H03n9: Operation not permitted
RC=1
```

The other broad-run failures have not been fully attributed. No broad-suite pass or review-gate pass is claimed. A derived lane-liveness cache first appeared under the pinned worktree during the broad run; only the two newly generated cache entries were removed after the runner exited. No tracked runtime-state changes are included.

## Closure evidence

The real haiku worker completed and all foreground commands were awaited. The focused suites and three negative controls pass their intended checks. Required remaining proofs are a completed green changed-scope run and the explicitly requested live work-slot HTTP-401 auction. The currently successful live usage endpoint cannot supply the latter condition.
