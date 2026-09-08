# Registry failure keeps a launchable arm

The registry enumeration failure in `_arm_launchable_arms` previously returned 1 and empty stdout. Its consumers treated that unknown set as empty, removing capable candidates. The helper now returns `glm,codex,sonnet` on query failure, discards partial query stdout, and emits `launchable_seam source=legacy reason=launch_registry_unavailable fallback=glm,codex,sonnet`. Successful registry results, including an empty result, remain authoritative.

`_filter_arms_to_dispatchable` now labels exclusions `reason=not_in_launchable_arms`, matching the computed set. The fallback applies at the shared helper, covering arbiter input, all three v2 adoption sites, and the ladder tail. The launch registry's separate adapter lookup is unchanged. The cause of the enumeration failure was not investigated.

Production write: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`. Regression write: `plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh`. The remaining files are this requested report and its evidence. `tests/run-all.sh` was not edited; no registration edit is needed because the new suite declares `# run-all-triggers: leadv2-dispatch-code`.

## Evidence: bash -n and python3 -m py_compile

```text
bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh
rc=0
bash -n plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh
rc=0
git diff --check
rc=0
python3 -m py_compile: no Python files changed. The suite's embedded Python was executed in every regression run.
```

## Evidence: test-registry-failure-keeps-a-launchable-arm.sh before fix (RED)

The suite injects `print('opus'); sys.exit(17)` inside the inline Python query in `_arm_launchable_arms`, with a unique function-body anchor. This tests a nonzero exit with partial stdout. It does not insert a top-level failure or disable the separate per-arm launch adapter registry.

```bash
git show f0060e5679a3826c750a0ed29c85bccd1a5f3a29:plugins/leadv2/scripts/leadv2-dispatch-code.sh > /tmp/registry-failure-before.sh
REGISTRY_FAILURE_DISPATCH_BIN=/tmp/registry-failure-before.sh timeout 150 bash plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh
# rc=1
```
```text
PASS: fallback expectation matches hardcoded legacy ladder: actual=['glm', 'codex', 'sonnet'] expected=['glm', 'codex', 'sonnet']
PASS: faulted dispatcher syntax: actual=0 expected=0
FAIL: registry outage status becomes usable fallback: actual=1 expected=0
FAIL: registry outage fallback VALUE (partial stdout discarded): actual='' expected='glm,codex,sonnet'
FAIL: degraded diagnostic names fallback source: actual=False expected=True
FAIL: initial survivor VALUE: actual='4:' expected='0:codex sonnet'
FAIL: initial false legacy-member drop records: actual=['decision arm_dropped_not_dispatchable arm=codex task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=initial', 'decision arm_dropped_not_dispatchable arm=sonnet task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=initial'] expected=[]
FAIL: initial reason describes computed launchability set: actual=True expected=False
FAIL: quota_filter survivor VALUE: actual='4:' expected='0:codex sonnet'
FAIL: quota_filter false legacy-member drop records: actual=['decision arm_dropped_not_dispatchable arm=codex task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_filter', 'decision arm_dropped_not_dispatchable arm=sonnet task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_filter'] expected=[]
FAIL: quota_filter reason describes computed launchability set: actual=True expected=False
FAIL: quota_gate survivor VALUE: actual='4:' expected='0:codex sonnet'
FAIL: quota_gate false legacy-member drop records: actual=['decision arm_dropped_not_dispatchable arm=codex task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_gate', 'decision arm_dropped_not_dispatchable arm=sonnet task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_gate'] expected=[]
FAIL: quota_gate reason describes computed launchability set: actual=True expected=False
FAIL: fallback tail retains legacy members, excludes unknown: actual='codex' expected='codex glm sonnet'
PASS: successful empty registry VALUE/status: actual=(0, '') expected=(0, '')
PASS: successful empty registry is not degraded: actual=False expected=False
PASS: successful registry VALUE is preserved: actual=(0, 'fable') expected=(0, 'fable')
PASS: successful registry names registry source: actual=True expected=True
FAIL: full dispatcher launched worker adapter VALUE (rc, model): actual=(4, None) expected=(0, 'sonnet')
[leadv2-dispatch-code] arm_pool_persisted task=4e31a2a8 pool=- pin=sonnet src=cli
[leadv2-dispatch-code] lane_plan_skipped task=4e31a2a8 reason=shared_tree
[leadv2-dispatch-code] task_class=Standard route=phases source=flag task=4e31a2a8
[leadv2-dispatch-code] complexity_gate_applied task=4e31a2a8 complexity=standard complexity_source=judge pipeline_route=plan_first forced_plan=0 review_rounds=2
[leadv2-dispatch-code] task_class_override by=admission task=4e31a2a8 requested=standard resolved=Standard reason=classifier_estimate source=flag
[leadv2-dispatch-code] class_floor_held task=4e31a2a8 declared=Standard computed=Standard
[leadv2-dispatch-code] brain_decision task=4e31a2a8 class=Standard class_source=floor_held phases=classify,plan,gate1,build,test,review,deploy,live_verify,close reason=declared_floor
[leadv2-dispatch-code] dispatch_classified task=4e31a2a8 class=product reason=conservative_default kind=code asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] lane_writes task=4e31a2a8 source=row writes=src/fixture.py
[leadv2-dispatch-code] mission_writeset_gate_disabled task=4e31a2a8 reason=REQUIRE_MISSION_WRITESET=0 note=no_write_scope_check_ran
[leadv2-dispatch-code] architect_prepass task=4e31a2a8 status=disabled reason=kill_switch
[leadv2-dispatch-code] protection_derived by=router task=4e31a2a8 writes=src/fixture.py write_class=standard writes_protected=0 manual_protected=0 effective_protected=0
[leadv2-dispatch-code] arm_resolved job=build arm=glm-flash reason=none complexity=standard duration_class=unknown
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=4e31a2a8 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=4e31a2a8 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=4e31a2a8 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_refused task=4e31a2a8 reason=launch_registry_unavailable kind=code
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=refuse task=4e31a2a8 reason=requested_arm_not_launchable requested_arm=sonnet util_glm=99 util_codex=20 util_claude=20 util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=5.00h_default_full_period reset_freepool=n/a failure_memory=no_history arm_excluded=codex:not_launchable,freepool:not_launchable,glm:not_launchable,glm-flash:not_launchable,sonnet:not_launchable arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e
[leadv2-dispatch-code] model_select_telemetry task=4e31a2a8 role=worker class=standard work_kind=code arm=refuse model=refuse fallback_depth=0 floor=none spawn_to_terminal_s=2 terminal=fail cause=requested_arm_not_launchable
[leadv2-dispatch-code] active_lane_release_skipped task=4e31a2a8 id=dispatch-4e31a2a8 where=exit_trap reason=not_owner_row_intact rows=1 removed=0 live_worker_kept=0

FAIL: full dispatcher confirms spawn: actual=False expected=True
SUMMARY: failures=15
```

## Evidence: test-registry-failure-keeps-a-launchable-arm.sh membership distinction (RED)

The [membership mutation](mutation-control/membership.patch) deliberately removes codex from the survivor array while retaining sonnet, and restores the misleading static-allowlist reason. The first failing assertion is the survivor VALUE, `0:sonnet` versus `0:codex sonnet`. The full worker-adapter launch still passes, so this catches loss of a capable arm even when another arm succeeds.

```bash
REGISTRY_FAILURE_DISPATCH_BIN=/tmp/registry-failure-membership.sh timeout 150 bash plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh
# rc=1; the mutant is the fixed dispatcher with membership.patch applied
```
```text
PASS: fallback expectation matches hardcoded legacy ladder: actual=['glm', 'codex', 'sonnet'] expected=['glm', 'codex', 'sonnet']
PASS: faulted dispatcher syntax: actual=0 expected=0
PASS: registry outage status becomes usable fallback: actual=0 expected=0
PASS: registry outage fallback VALUE (partial stdout discarded): actual='glm,codex,sonnet' expected='glm,codex,sonnet'
PASS: degraded diagnostic names fallback source: actual=True expected=True
FAIL: initial survivor VALUE: actual='0:sonnet' expected='0:codex sonnet'
FAIL: initial false legacy-member drop records: actual=['decision arm_dropped_not_dispatchable arm=codex task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=initial'] expected=[]
FAIL: initial reason describes computed launchability set: actual=True expected=False
FAIL: quota_filter survivor VALUE: actual='0:sonnet' expected='0:codex sonnet'
FAIL: quota_filter false legacy-member drop records: actual=['decision arm_dropped_not_dispatchable arm=codex task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_filter'] expected=[]
FAIL: quota_filter reason describes computed launchability set: actual=True expected=False
FAIL: quota_gate survivor VALUE: actual='0:sonnet' expected='0:codex sonnet'
FAIL: quota_gate false legacy-member drop records: actual=['decision arm_dropped_not_dispatchable arm=codex task=t router=v2 reason=not_in_DISPATCHABLE_BUILD_ARMS site=quota_gate'] expected=[]
FAIL: quota_gate reason describes computed launchability set: actual=True expected=False
PASS: fallback tail retains legacy members, excludes unknown: actual='codex glm sonnet' expected='codex glm sonnet'
PASS: successful empty registry VALUE/status: actual=(0, '') expected=(0, '')
PASS: successful empty registry is not degraded: actual=False expected=False
PASS: successful registry VALUE is preserved: actual=(0, 'fable') expected=(0, 'fable')
PASS: successful registry names registry source: actual=True expected=True
PASS: full dispatcher launched worker adapter VALUE (rc, model): actual=(0, 'sonnet') expected=(0, 'sonnet')
PASS: full dispatcher confirms spawn: actual=True expected=True
SUMMARY: failures=9
```

## Evidence: test-registry-failure-keeps-a-launchable-arm.sh restored fix (GREEN)

The restored suite is green after both red runs. The full dispatcher executes a local capturing Sonnet worker adapter, checks its supplied live fixture PID, and emits the spawn confirmation. The assertion checks the dispatcher exit code and the captured `--model` argument; it cannot pass on a success log alone. Quota responses and launch adapters are offline fixtures; no model/provider launch is claimed.

```bash
timeout 150 bash plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh
# rc=0
```
```text
PASS: fallback expectation matches hardcoded legacy ladder: actual=['glm', 'codex', 'sonnet'] expected=['glm', 'codex', 'sonnet']
PASS: faulted dispatcher syntax: actual=0 expected=0
PASS: registry outage status becomes usable fallback: actual=0 expected=0
PASS: registry outage fallback VALUE (partial stdout discarded): actual='glm,codex,sonnet' expected='glm,codex,sonnet'
PASS: degraded diagnostic names fallback source: actual=True expected=True
PASS: initial survivor VALUE: actual='0:codex sonnet' expected='0:codex sonnet'
PASS: initial false legacy-member drop records: actual=[] expected=[]
PASS: initial reason describes computed launchability set: actual=False expected=False
PASS: quota_filter survivor VALUE: actual='0:codex sonnet' expected='0:codex sonnet'
PASS: quota_filter false legacy-member drop records: actual=[] expected=[]
PASS: quota_filter reason describes computed launchability set: actual=False expected=False
PASS: quota_gate survivor VALUE: actual='0:codex sonnet' expected='0:codex sonnet'
PASS: quota_gate false legacy-member drop records: actual=[] expected=[]
PASS: quota_gate reason describes computed launchability set: actual=False expected=False
PASS: fallback tail retains legacy members, excludes unknown: actual='codex glm sonnet' expected='codex glm sonnet'
PASS: successful empty registry VALUE/status: actual=(0, '') expected=(0, '')
PASS: successful empty registry is not degraded: actual=False expected=False
PASS: successful registry VALUE is preserved: actual=(0, 'fable') expected=(0, 'fable')
PASS: successful registry names registry source: actual=True expected=True
PASS: full dispatcher launched worker adapter VALUE (rc, model): actual=(0, 'sonnet') expected=(0, 'sonnet')
PASS: full dispatcher confirms spawn: actual=True expected=True
SUMMARY: failures=0
```

## Evidence: leadv2-mutation-control.sh

The official helper reruns the green suite in a scratch snapshot before applying each committed patch, then requires the mutated suite to fail. The [fallback artifact](mutation-control/fallback.txt) and [membership artifact](mutation-control/membership.txt) contain the raw helper evidence, including baseline/mutated return values, failing value assertion, applied-diff hash, and lane-diff hash. Their companion [fallback transcript](mutation-control/fallback.log) and [membership transcript](mutation-control/membership.log) contain the raw helper stdout. These artifacts are generated after committing this report so their lane identity includes the report; only `mutation-control/` files are subsequently committed, matching the helper's documented hash exclusion.

```bash
timeout -k 10 240 bash plugins/leadv2/scripts/leadv2-mutation-control.sh plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh plugins/leadv2/scripts/leadv2-dispatch-code.sh docs/handoff/dispatch-d60b1e07/mutation-control/fallback.patch docs/handoff/dispatch-d60b1e07
timeout -k 10 240 bash plugins/leadv2/scripts/leadv2-mutation-control.sh plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh plugins/leadv2/scripts/leadv2-dispatch-code.sh docs/handoff/dispatch-d60b1e07/mutation-control/membership.patch docs/handoff/dispatch-d60b1e07
```

## Evidence: tests/run-all.sh --scope changed selection

The production dispatcher was dirty when this selection was run. The new suite was untracked, so its selection was driven by the dispatcher trigger, not by a changed test selecting itself.

```bash
LEADV2_RUN_ALL_SELECT_ONLY=1 timeout 30 bash tests/run-all.sh --scope changed
# rc=0
```
```text
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-arm-pool-reachability.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-exclusion-stages.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-admission-safety-pin.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-admission.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-advance-real.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-burn-governor.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-codex-instant-complete.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-codex-refusal-cause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-complexity-routing.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-checkpoint-commit-cutoff.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-outcome-terminal-retry.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-usage-names-the-fault-last.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-effort-routing.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-freepool-gets-work.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-flash-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-landed-at-spawn.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-containment.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-placement-pin.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-writes-rejection-is-named.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lead-worker-channel.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-leadv2-dispatch-outcome-ledger.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-mission-writeset.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-model-select-telemetry.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-gate-default-class.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-gate-names-everything.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plan-in-lane.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plan-run-contract.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-papercuts.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-resume-invalidate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-red-proof-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-report-only-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-route-arbiter.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-single-writer-lane-state.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-spawn-handle-parse.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-st2-question-protocol.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-stale-script-tree.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-stop-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-t13-slice2.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-worker-ended-on-wait.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-worker-env-asserts.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-writeset-pending-overlap.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-complexity-source-provenance.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-dedup-release-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-kimi-admission-guard.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-kimi-dispatch-spill.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-lane-state-wiring.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-launch-uses-the-chosen-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-registry-failure-keeps-a-launchable-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-router-v2-shadow-mode.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/tests/test-unmetered-account-not-penalised.sh
run-all: 114 selected, scope=changed, select_only=1
```

## Evidence: tests/run-all.sh --scope changed execution

BLOCKED: the required changed-scope gate did not pass. The wrapper reached its explicit 1,200-second bound and exited 124 while its core runner was still executing. The partial shard output below contains failed assertions and sandbox-denied fixture creation. This is not a completed CI pass, and the partial output does not establish the cause of every failure.

```bash
timeout -k 10 1200 bash tests/run-all.sh --scope changed > /tmp/registry-failure-changed-scope.log 2>&1
# rc=124
```

Raw wrapper output (the final rc line was appended by the invoking shell):
```text
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh

changed_scope_rc=124
```

The wrapper captures the core runner's stdout until it exits. The following is its raw captured output, recovered separately:
```text
[CORE-OFFLINE] scope=changed running 111 of 95 suites (base=main@34e9fefa05, 2 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=111 total=95 base=main@34e9fefa05 changed=2 unmapped=0 verdict=selected reason=-
[CORE-OFFLINE] running 111 suites across 4 shards
```

### Evidence: baseline reproduction of the temporary-directory denial

One gate failure was reproduced using the pre-fix dispatcher and the unchanged `test-worker-env-asserts.sh` in a minimal temporary fixture. With `TMPDIR` unset, it failed at temporary-directory creation before reaching the dispatcher assertions. This establishes that specific environment failure on the baseline; the other gate failures remain untriaged.

```bash
mkdir -p /tmp/registry-failure-baseline/scripts/tests
cp /tmp/registry-failure-before.sh /tmp/registry-failure-baseline/scripts/leadv2-dispatch-code.sh
cp plugins/leadv2/scripts/tests/test-worker-env-asserts.sh /tmp/registry-failure-baseline/scripts/tests/test-worker-env-asserts.sh
env -u TMPDIR timeout 15 bash /tmp/registry-failure-baseline/scripts/tests/test-worker-env-asserts.sh
# rc=1
```
```text
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.dUIsKM8Elo: Operation not permitted
```

### Evidence: changed-scope core shard 0, partial raw output

```text

[CORE-OFFLINE] all plugin shell syntax

[CORE-OFFLINE] landed-at-spawn (no terminal=landed at spawn; target repo keying)
[TEST] PASS: T-a: dispatch exited 0 (spawn succeeded)
[TEST] PASS: T-a: no terminal=landed in TARGET terminal ledger
[TEST] PASS: T-a: no terminal=landed in DECOY terminal ledger
[TEST] PASS: T-a: reservation ledger has a row for this sig
[TEST] PASS: T-a: reservation row is confirmed
[TEST] PASS: T-b: dispatch exited 4 (pre-spawn refusal)
[TEST] PASS: T-b: terminal row landed in TARGET state dir for sig b195e743
[TEST] PASS: T-d: NO terminal row in DECOY state dir for sig b195e743
[TEST] PASS: T-c: terminal ledger is non-empty (pre-spawn refusal still writes)
[TEST] PASS: T-c: terminal row has terminal=refused
[TEST] PASS: T-c: terminal row has cause=all_arms_excluded
[TEST] PASS: T-static: no _dl_note landed/spawned_ call in dispatch-code.sh

[LANDED-AT-SPAWN-01] passed=12 failed=0

[CORE-OFFLINE] foreground-dispatch guard hook
[TEST] PASS: foreground dispatch denied with correct message
[TEST] PASS: trailing-& dispatch allowed
[TEST] PASS: run_in_background=true allowed
[TEST] PASS: absent run_in_background + no & denied
[TEST] PASS: --no-spawn allowed
[TEST] PASS: LEADV2_DISPATCH_SPAWN=0 allowed
[TEST] PASS: --help allowed
[TEST] PASS: status subcommand allowed
[TEST] PASS: record-review subcommand allowed
[TEST] PASS: # fg-dispatch: allow override works
[TEST] PASS: LEADV2_ALLOW_FG_DISPATCH=1 env override works
[TEST] PASS: non-matching command allowed
[TEST] PASS: empty stdin allowed
[TEST] PASS: malformed JSON allowed
[TEST] PASS: leadv2-codex-session-runner.sh foreground denied
[TEST] PASS: leadv2-fanout.sh foreground denied
[TEST] PASS: glm-coder.sh foreground denied
[TEST] PASS: omp-task.sh foreground denied
[TEST] PASS: && correctly not treated as backgrounded
[TEST] PASS: &> correctly not treated as backgrounded
[TEST] PASS: nohup & allowed
[TEST] PASS: setsid denied on macOS (setsid absent, R9)
[TEST] PASS: hooks.json valid and hook field-parsed as a MANIFEST record
[TEST] PASS: guard selected at runtime for a trigger-matching command (LEADV2_DISPATCH_TRACE=1)
[TEST] PASS: status-surface sibling segment correctly does not exempt dispatch
[TEST] PASS: git status sibling does not exempt dispatch (F1 &&)
[TEST] PASS: git status after ; does not exempt dispatch (F1 ;)
[TEST] PASS: --help sibling does not exempt dispatch (F1 --help)
[TEST] PASS: real status subcommand still allowed
[TEST] PASS: real --no-spawn flag still allowed
[TEST] PASS: cat launcher allowed with no override and no stderr (F2)
[TEST] PASS: git log launcher path allowed with no stderr (F2)
[TEST] PASS: background dispatch survives segmentation
[TEST] PASS: quoted launcher in echo correctly ignored; real dispatch denied
[TEST] PASS: dispatch piped to tee correctly denied (segment is foreground)
[TEST] PASS: grep for fanout launcher allowed with no stderr (F2 second launcher)

[fg-dispatch-guard] PASS=36 FAIL=0

[CORE-OFFLINE] worker ends turn on a wait (contract + detector + salvage)
[TEST] PASS (a) wait shape recognised: I'll wait for the background job t…
[TEST] PASS (a) wait shape recognised: Waiting for the review to come bac…
[TEST] PASS (a) wait shape recognised: I will wait — before proceeding I …
[TEST] PASS (b) NEG-CTL: normal completion is not a wait: Landed the fix and committed it as…
[TEST] PASS (b) NEG-CTL: normal completion is not a wait: Suite is 12/0; report written to d…
[TEST] PASS (b) NEG-CTL: normal completion is not a wait: BLOCKED: the API key is missing — …
[TEST] PASS (c) uncommitted lane work is salvaged into a commit
[TEST] PASS (c2) a file outside the write set is left uncommitted (no add -A)
[TEST] PASS (d) a clean lane reports nothing_to_commit
[TEST] PASS (e) an unidentified tree is never committed into
[TEST] PASS (f) no declared write set -> refuses, and commits nothing
[TEST] PASS (g) a wait-shaped stop is journaled and the lane is committed
[TEST] PASS (h) NEG-CTL: a normal stop journals nothing and commits nothing
[TEST] PASS (i) LEADV2_WORKER_ENDED_ON_WAIT=0 stops it
[TEST] PASS (j) the dispatched mission carries the ## Waiting contract
[TEST] 15 passed, 0 failed

[CORE-OFFLINE] worker env asserts (V3-ENV-GUARDS-01)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.awaV7RJpL1: Operation not permitted
[CORE-OFFLINE] FAILED: worker env asserts (V3-ENV-GUARDS-01)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: run path: GLM_EFFORT=max -> spawn argv carries --effort max (deepthink transport)
[TEST] PASS: dispatch: Heavy -> journal effort=max think=deep source=class_map
[TEST] PASS: dispatch: Heavy -> launcher env GLM_EFFORT=max (deepthink reaches the runner variable)
[TEST] PASS: dispatch: Strategic -> journal effort=max think=deep source=class_map
[TEST] PASS: dispatch: Strategic -> launcher env GLM_EFFORT=max (deepthink reaches the runner variable)
[TEST] PASS: dispatch: Heavy +critic -> journal effort=max think=deep source=think_deep
[TEST] PASS: dispatch: Heavy +critic -> launcher env GLM_EFFORT=max (deepthink reaches the runner variable)
[TEST] PASS: dispatch: Standard -> journal effort=high think=off source=class_map
[TEST] PASS: dispatch: Standard -> launcher env GLM_EFFORT=high (deepthink reaches the runner variable)
[TEST] PASS: dispatch: Light -> journal effort=low think=off source=class_map
[TEST] PASS: dispatch: Light -> launcher env GLM_EFFORT=low (deepthink reaches the runner variable)
[TEST] PASS: map: trivial -> off class_map
[TEST] PASS: map: light -> off class_map
[TEST] PASS: map: bulk -> off class_map
[TEST] PASS: map: standard -> off class_map
[TEST] PASS: map: heavy -> deep class_map
[TEST] PASS: map: strategic -> deep class_map
[TEST] PASS: map: Heavy -> deep class_map
[TEST] PASS: map: Strategic -> deep class_map
[TEST] PASS: map: Light -> off class_map
[TEST] PASS: map: bogus-cls -> off fallback
[TEST] summary: PASS=23 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh (scope-selected ad-hoc)
PASS: bash syntax: dispatch
PASS: (green) router still excludes freepool for a light task (when=standard,bulk)
PASS: (green) arbiter honours the router's exclusion -- freepool never arbiter_pick
PASS: (red) with allowed_arms wiring stripped, the exact live bug reproduces -- arbiter re-picks the router-excluded arm
---
PASS=4 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-brain-class-live.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.6RqsY8OBxR: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
FAIL: (a) missing class_escalated line: [leadv2-dispatch-code] task_class=Standard route=phases source=classifier_error task=brainA01
[leadv2-dispatch-code] complexity_gate_applied task=brainA01 complexity=standard complexity_source=flag pipeline_route=plan_first forced_plan=0 review_rounds=2
[leadv2-dispatch-code] task_class_override by=admission task=brainA01 requested=light resolved=Standard reason=classifier_error_fallback source=classifier_error
[leadv2-dispatch-code] brain_decision task=brainA01 class=Standard class_source=declared_fallback phases=classify,plan,gate1,build,test,review,live_verify,close reason=judge_unavailable
CLASS=Standard SOURCE=classifier_error
FAIL: (a) brain.yaml missing or wrong class_source
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.pYuuCqqLVt: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
FAIL: (b) missing class_floor_held line: [leadv2-dispatch-code] task_class=Heavy route=phases source=classifier_error task=brainB01
[leadv2-dispatch-code] complexity_gate_applied task=brainB01 complexity=complex complexity_source=flag pipeline_route=plan_first forced_plan=0 review_rounds=3
[leadv2-dispatch-code] task_class_override by=admission task=brainB01 requested=heavy resolved=Heavy reason=classifier_error_fallback source=classifier_error
[leadv2-dispatch-code] brain_decision task=brainB01 class=Heavy class_source=declared_fallback phases=classify,diverge,plan,gate1,build,test,review,live_verify,e2e,close reason=judge_unavailable
CLASS=Heavy SOURCE=classifier_error
PASS: (b) final class stays Heavy
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.uEJyD5lA6H: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 41: /judge-fail.sh: Operation not permitted
chmod: /judge-fail.sh: No such file or directory
PASS: (c) judge failure -> declared_fallback
PASS: (c) dispatch proceeds with declared class, no refusal
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.sy9pFuHG7g: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 41: /judge-fail.sh: Operation not permitted
chmod: /judge-fail.sh: No such file or directory
PASS: (c2) judge failure + declared=Heavy floors admission class at Heavy
FAIL: (c2) brain.yaml missing or wrong class for judge-fail floor
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.l6CC8b6yf4: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 41: /judge-fail.sh: Operation not permitted
chmod: /judge-fail.sh: No such file or directory
PASS: (c3) judge failure + declared=Strategic floors admission class at Strategic
FAIL: (c3) brain.yaml missing or wrong class for judge-fail floor
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.fLbFc2cxj9: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 41: /judge-fail.sh: Operation not permitted
chmod: /judge-fail.sh: No such file or directory
PASS: (c4) judge failure + declared=Light never lowers below Standard
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.xJVTkSW47u: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
PASS: (c5-up) judge success escalates over a lower declared class
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.fjrzwW5pNS: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
PASS: (c5-down) declared floor holds Heavy over a lower judge-computed class
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.p3SkRXlUQu: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
FAIL: (d) brain_decision line missing/wrong: [leadv2-dispatch-code] task_class=Standard route=phases source=classifier_error task=brainD01
[leadv2-dispatch-code] complexity_gate_applied task=brainD01 complexity=standard complexity_source=flag pipeline_route=plan_first forced_plan=0 review_rounds=2
[leadv2-dispatch-code] task_class_override by=admission task=brainD01 requested=light resolved=Standard reason=classifier_error_fallback source=classifier_error
[leadv2-dispatch-code] brain_decision task=brainD01 class=Standard class_source=declared_fallback phases=classify,plan,gate1,build,test,review,live_verify,close reason=judge_unavailable
CLASS=Standard SOURCE=classifier_error
FAIL: (d) brain.yaml class mismatch
mktemp: mkstemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.VgtxmRcfMz: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 252: : No such file or directory
cat: : No such file or directory
FAIL: (d) re-entry floor did not return Heavy on stdout: stdout='' stderr=''
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.xhK3ggt2sk: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
PASS: (e) brain_decision reaches stderr with JOURNAL_TASK unset
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.V1gR7mHU05: Operation not permitted
cp: /leadv2-dispatch-code.sh: Operation not permitted
cp: /lib: Operation not permitted
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/leadv2-dispatch-code.sh'
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.s6OXN2gPOr: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
PASS: MUTATION (e) killed: re-adding 2>/dev/null drops brain_decision from stderr
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.ljRyFsUWba: Operation not permitted
cp: /leadv2-dispatch-code.sh: Operation not permitted
cp: /lib: Operation not permitted
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/leadv2-dispatch-code.sh'
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.s461qEKIQg: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
mktemp: mkstemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.mvoVk6HIIQ: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 366: : No such file or directory
cat: : No such file or directory
FAIL: MUTATION (d-re-entry) inconclusive: expected the decision line to still mention Heavy on stderr even though stdout is stale, got stdout='' stderr=''
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.EC4waM4u60: Operation not permitted
cp: /scripts: Operation not permitted
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.UvlfFka781: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
FAIL: (a) baseline FAILED on unmutated full copy -- control not comparable to tracked file: out=_: line 2: /scripts/leadv2-dispatch-code.sh: No such file or directory
_: line 3: _admission_classify: command not found
CLASS= SOURCE=
FAIL: (d) baseline FAILED: unmutated full copy did not write brain.yaml
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/scripts/leadv2-dispatch-code.sh'
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.4xKJ7dAHoI: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 29: /judge-stub.sh: Operation not permitted
chmod: /judge-stub.sh: No such file or directory
PASS: MUTATION (a) killed: no class_escalated when judge call is skipped
PASS: MUTATION (d) killed: no brain.yaml written when judge call is skipped
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.2UigUZaLso: Operation not permitted
cp: /leadv2-dispatch-code.sh: Operation not permitted
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/leadv2-dispatch-code.sh'
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.nV9u5tuaND: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-brain-class-live.sh: line 41: /judge-fail.sh: Operation not permitted
chmod: /judge-fail.sh: No such file or directory
PASS: MUTATION (c2) killed: reverting to hard-coded Standard loses the Heavy floor

=== test-brain-class-live.sh: 13 PASS, 11 FAIL ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-brain-class-live.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.SBCyjEz8lN: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.5NpXP6u9Sn: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh: line 27: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh: line 28: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh: line 30: /worker: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh: line 31: /architect: Operation not permitted
chmod: /worker: No such file or directory
chmod: /architect: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh: line 64: cd: /repo: No such file or directory
grep: /out.log: No such file or directory
FAIL a design that landed on disk a beat late was not accepted as ran:
cat: /out.log: No such file or directory
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh (scope-selected ad-hoc)
[TEST] PASS: exactly one racer wins (rc=0), exactly one is refused (rc=2)
[TEST] FAIL: setup: no sig8 extracted from dispatch output, or ledger file never created (out_a=[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=71ba32fc status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=71ba32fc reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/71ba32fc/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=71ba32fc
[leadv2-dispatch-code] complexity_gate_applied task=71ba32fc complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=71ba32fc class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=71ba32fc founder_task=71ba32fc complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/71ba32fc/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=71ba32fc class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] phase_precondition_bootstrap task=71ba32fc class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=71ba32fc writes=<none> write_class=unknown writes_protected=1 manual_protected=1 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=71ba32fc reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=71ba32fc reason=protected_path
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=71ba32fc
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=71ba32fc reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=71ba32fc arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=glm task=71ba32fc mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm task=71ba32fc effort=high think=off think_source=class_map mechanism=flag source=class_map resolved=high
[leadv2-dispatch-code] spawn_failed by=router model=glm task=71ba32fc rc=1 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(glm) failed rc=1:  [glm-quota-gate] FAIL-OPEN: GLM quota read is unknown (ZAI_AUTH_TOKEN not set / not readable). Cannot gate on a number we do not have — lane may start.
[2026-09-08 14:43:06] ERROR: secrets file not found: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/home/.claude/secrets/zai.env
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/leadv2-dispatch-spawn-71ba32fc.stderr.log

[leadv2-dispatch-code] route_fallback from=glm to=codex task=71ba32fc reason=glm_failed_launcher
[leadv2-dispatch-code] worker_env_assert arm=codex task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=codex task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=codex task=71ba32fc mode=none reason=arm_unwired cause=codex_no_mcp_wiring
[leadv2-dispatch-code] spawn_failed by=router model=codex task=71ba32fc rc=1 reason=launcher_nonzero_exit detail=<launcher-stderr-empty>
[leadv2-dispatch-code] ERROR: spawn(codex) failed rc=1:  

[leadv2-dispatch-code] route_fallback from=codex to=sonnet task=71ba32fc reason=codex_failed_launcher
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=sonnet task=71ba32fc mode=attached
[leadv2-dispatch-code] launch_model_resolved task=71ba32fc task_id=dispatch-71ba32fc arm=sonnet resolved_model=sonnet
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=71ba32fc attempt=71ba32fc-1788867739-71188 handle=PID=95108 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] mission-version task=- sig=71ba32fc rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
worker_spawned model=sonnet task=71ba32fc attempt=71ba32fc-1788867739-71188 handle=PID=95108 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=sonnet task=71ba32fc rule=none reason=cheapest_capable arbiter_pick=glm arm_source=ladder_fallback depth=2 after=codex_failed_launcher
route_resolved by=router router=arbiter model=sonnet task=71ba32fc rule=none reason=cheapest_capable arbiter_pick=glm arm_source=ladder_fallback depth=2 after=codex_failed_launcher
[leadv2-dispatch-code] model_select_telemetry task=71ba32fc role=worker class=standard work_kind=build arm=sonnet model=sonnet fallback_depth=2 floor=none spawn_to_terminal_s=45 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=71ba32fc founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/71ba32fc
[leadv2-dispatch-code] lane worktree left on disk for task=71ba32fc: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/71ba32fc out_b=[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=71ba32fc status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=71ba32fc reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/71ba32fc/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=71ba32fc
[leadv2-dispatch-code] complexity_gate_applied task=71ba32fc complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=71ba32fc class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=71ba32fc founder_task=71ba32fc complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/71ba32fc/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=71ba32fc class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] phase_precondition_bootstrap task=71ba32fc class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=71ba32fc writes=<none> write_class=unknown writes_protected=1 manual_protected=1 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=71ba32fc reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=71ba32fc reason=protected_path
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=71ba32fc
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=71ba32fc reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=71ba32fc arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=glm task=71ba32fc mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm task=71ba32fc effort=high think=off think_source=class_map mechanism=flag source=class_map resolved=high
[leadv2-dispatch-code] spawn_failed by=router model=glm task=71ba32fc rc=1 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(glm) failed rc=1:  [glm-quota-gate] FAIL-OPEN: GLM quota read is unknown (ZAI_AUTH_TOKEN not set / not readable). Cannot gate on a number we do not have — lane may start.
[2026-09-08 14:43:04] ERROR: secrets file not found: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/home/.claude/secrets/zai.env
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/leadv2-dispatch-spawn-71ba32fc.stderr.log

[leadv2-dispatch-code] route_fallback from=glm to=codex task=71ba32fc reason=glm_failed_launcher
[leadv2-dispatch-code] dispatch_refused reason=duplicate_task_signature task=71ba32fc ledger=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/cache/dispatch-ledger/leadv2.jsonl
dispatch_refused reason=duplicate_task_signature task=71ba32fc
[leadv2-dispatch-code] active_lane_release_skipped task=71ba32fc id=dispatch-71ba32fc where=exit_trap reason=not_owner_row_intact rows=1 removed=0 live_worker_kept=0)

[TEST] 1 passed, 1 failed
[TEST] Failures:
  - setup: no sig8 extracted from dispatch output, or ledger file never created (out_a=[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=71ba32fc status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=71ba32fc reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/71ba32fc/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=71ba32fc
[leadv2-dispatch-code] complexity_gate_applied task=71ba32fc complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=71ba32fc class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=71ba32fc founder_task=71ba32fc complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/71ba32fc/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=71ba32fc class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] phase_precondition_bootstrap task=71ba32fc class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=71ba32fc writes=<none> write_class=unknown writes_protected=1 manual_protected=1 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=71ba32fc reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=71ba32fc reason=protected_path
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=71ba32fc
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=71ba32fc reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=71ba32fc arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=glm task=71ba32fc mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm task=71ba32fc effort=high think=off think_source=class_map mechanism=flag source=class_map resolved=high
[leadv2-dispatch-code] spawn_failed by=router model=glm task=71ba32fc rc=1 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(glm) failed rc=1:  [glm-quota-gate] FAIL-OPEN: GLM quota read is unknown (ZAI_AUTH_TOKEN not set / not readable). Cannot gate on a number we do not have — lane may start.
[2026-09-08 14:43:06] ERROR: secrets file not found: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/home/.claude/secrets/zai.env
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/leadv2-dispatch-spawn-71ba32fc.stderr.log

[leadv2-dispatch-code] route_fallback from=glm to=codex task=71ba32fc reason=glm_failed_launcher
[leadv2-dispatch-code] worker_env_assert arm=codex task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=codex task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=codex task=71ba32fc mode=none reason=arm_unwired cause=codex_no_mcp_wiring
[leadv2-dispatch-code] spawn_failed by=router model=codex task=71ba32fc rc=1 reason=launcher_nonzero_exit detail=<launcher-stderr-empty>
[leadv2-dispatch-code] ERROR: spawn(codex) failed rc=1:  

[leadv2-dispatch-code] route_fallback from=codex to=sonnet task=71ba32fc reason=codex_failed_launcher
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=sonnet task=71ba32fc mode=attached
[leadv2-dispatch-code] launch_model_resolved task=71ba32fc task_id=dispatch-71ba32fc arm=sonnet resolved_model=sonnet
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=71ba32fc attempt=71ba32fc-1788867739-71188 handle=PID=95108 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] mission-version task=- sig=71ba32fc rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
worker_spawned model=sonnet task=71ba32fc attempt=71ba32fc-1788867739-71188 handle=PID=95108 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=sonnet task=71ba32fc rule=none reason=cheapest_capable arbiter_pick=glm arm_source=ladder_fallback depth=2 after=codex_failed_launcher
route_resolved by=router router=arbiter model=sonnet task=71ba32fc rule=none reason=cheapest_capable arbiter_pick=glm arm_source=ladder_fallback depth=2 after=codex_failed_launcher
[leadv2-dispatch-code] model_select_telemetry task=71ba32fc role=worker class=standard work_kind=build arm=sonnet model=sonnet fallback_depth=2 floor=none spawn_to_terminal_s=45 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=71ba32fc founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/71ba32fc
[leadv2-dispatch-code] lane worktree left on disk for task=71ba32fc: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/71ba32fc out_b=[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=71ba32fc status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=71ba32fc reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/71ba32fc/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=71ba32fc
[leadv2-dispatch-code] complexity_gate_applied task=71ba32fc complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=71ba32fc class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=71ba32fc founder_task=71ba32fc complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/71ba32fc/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=71ba32fc class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] phase_precondition_bootstrap task=71ba32fc class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=71ba32fc writes=<none> write_class=unknown writes_protected=1 manual_protected=1 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=71ba32fc reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=71ba32fc reason=protected_path
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=71ba32fc
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=71ba32fc source=registry kind=code
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=71ba32fc reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=71ba32fc arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=71ba32fc var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=glm task=71ba32fc mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm task=71ba32fc effort=high think=off think_source=class_map mechanism=flag source=class_map resolved=high
[leadv2-dispatch-code] spawn_failed by=router model=glm task=71ba32fc rc=1 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(glm) failed rc=1:  [glm-quota-gate] FAIL-OPEN: GLM quota read is unknown (ZAI_AUTH_TOKEN not set / not readable). Cannot gate on a number we do not have — lane may start.
[2026-09-08 14:43:04] ERROR: secrets file not found: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/home/.claude/secrets/zai.env
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/leadv2-dispatch-spawn-71ba32fc.stderr.log

[leadv2-dispatch-code] route_fallback from=glm to=codex task=71ba32fc reason=glm_failed_launcher
[leadv2-dispatch-code] dispatch_refused reason=duplicate_task_signature task=71ba32fc ledger=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.U7Vku0/dispatch-race-71067-1788867738.ZQvUzw/cache/dispatch-ledger/leadv2.jsonl
dispatch_refused reason=duplicate_task_signature task=71ba32fc
[leadv2-dispatch-code] active_lane_release_skipped task=71ba32fc id=dispatch-71ba32fc where=exit_trap reason=not_owner_row_intact rows=1 removed=0 live_worker_kept=0)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh (scope-selected ad-hoc)
[TEST] PASS: Codex success writes a design from an isolated disposable worktree
[TEST] PASS: GLM --out success is accepted and disposed
[TEST] PASS: nonzero provider result fails and removes the fallback workspace
[TEST] PASS: timeout kills the stubbed provider and removes the fallback workspace
[TEST] PASS: SIGTERM interrupts a 30-second fallback promptly and removes its workspace
[TEST] PASS: SIGTERM at fallback runner registration reaps the runner before any provider starts
[TEST] PASS: codex live-row signal window is disarmed before EXIT cleanup
[TEST] PASS: glm live-row signal window is disarmed before EXIT cleanup
[TEST] PASS: registry compare-and-delete refuses a foreign owner row
[TEST] PASS: registry compare-and-delete refuses a worker-owned row
[TEST] PASS: registry compare-and-delete removes only the captured owner row
[TEST] PASS: H4: empty evidence -> opaque failed_rc_1
[TEST] PASS: H4: stream.jsonl error=authentication_failed -> authentication_failed (live 17309830 shape)
[TEST] PASS: H4: captured stdout OAuth-expired text -> authentication_failed
[TEST] PASS: H4: 429/too-many-requests -> rate_limited
[TEST] PASS: H4: usage-limit text -> quota_exceeded
[TEST] PASS: H4: auth outranks quota when both match
[TEST] PASS: H4: unmatched text -> opaque failed_rc_<rc>

[SUITE] PASS: 18 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-effort-routing.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.xJDDY3MMC9: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-effort-routing.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh (scope-selected ad-hoc)
PASS: bash syntax: arbiter + dispatch
PASS: (b) standard build: freepool not selected (SELECTION outcome asserted, not just the journal line)
PASS: (b) standard build: floor journaled as floor_applied=1 floor_reason=standard/code
PASS: (b) standard build: freepool demoted to LAST chain position (codex,sonnet,freepool)
PASS: (b) standard build: codex and sonnet both rank ahead of freepool
PASS: (b) state file: JSON with arm + task=deadbeef stamp + floor bookkeeping
PASS: (b2) heavy build: freepool not selected
PASS: (b2) heavy build: no floor token when freepool is not in the candidate set
PASS: (b2) strategic build: freepool not selected
PASS: (b2) strategic build: no floor token when freepool is not in the candidate set
PASS: (c) bulk build: freepool still selectable
PASS: (c) bulk build: no floor token for bulk
FAIL: (c2) trivial build: freepool demoted for a simple task (arm=sonnet kind=code model=sonnet tier=standard effort=medium reason=capability_fit chain=sonnet,freepool util_glm=99 util_codex=99 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:capped,freepool:price_ratio,glm:capped,glm-flash:capped arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=sonnet fit_differs=1 fit_bucket=sonnet:0,freepool:1) -- 
FAIL: (c2) light build: freepool demoted for a simple task (arm=sonnet kind=code model=sonnet tier=standard effort=medium reason=capability_fit chain=sonnet,freepool util_glm=99 util_codex=99 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:capped,freepool:price_ratio,glm:capped,glm-flash:capped arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=sonnet fit_differs=1 fit_bucket=sonnet:0,freepool:1) -- 
FAIL: (c3) standard docs: freepool unexpectedly demoted (arm=codex kind=docs model=gpt-6-astra tier=volume effort=low reason=capability_fit chain=codex,sonnet,freepool,haiku util_glm=99 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:price_ratio,glm:capped,glm-flash:capped,haiku:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=80.0 reset_in=n/a reset_basis=unknown_window probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,freepool:1,haiku:1) -- 
PASS: (dispatch) arm_floor_applied journal line emitted from the arbiter's own output
PASS: (dispatch) route_resolved did not pick freepool (selection outcome)
FAIL: (a) bulk build did not resolve to freepool: [leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=sonnet model=sonnet tier=standard effort=medium task=4bfad34b reason=cheapest_capable arbiter_pick=sonnet util_glm=99 util_codex=99 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:capped,freepool:price_ratio,glm:capped,glm-flash:capped arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_applied=1 floor_reason=standard/code floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=sonnet fit_differs=0 fit_bucket=sonnet:0,freepool:1 -- 
PASS: (a) waiter did not declare no_work early (worker finishes at t+8s, window is 3s)
PASS: (a) freepool run finalized complete after the window
PASS: (a) run left a REAL diff on disk (diff.patch with hunks)
PASS: (negative-control) floor mutation applied to a throwaway arbiter copy
FAIL: (negative-control) mutated arbiter did not flip the winner — (b) is not load-bearing (arm=codex kind=code model=gpt-6-astra tier=volume effort=medium reason=capability_fit chain=codex,sonnet,freepool util_glm=99 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:price_ratio,glm:capped,glm-flash:capped,sonnet:price_ratio arb_rev=153454840e34 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=80.0 reset_in=n/a reset_basis=unknown_window probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,freepool:1) -- 
FAIL: (e1) env full: freepool still demoted (arm=codex kind=code model=gpt-6-astra tier=volume effort=medium reason=capability_fit chain=codex,sonnet,freepool util_glm=99 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:price_ratio,glm:capped,glm-flash:capped,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=full floor_mode_source=env test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=80.0 reset_in=n/a reset_basis=unknown_window probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,freepool:1) -- 
PASS: (e1) env full: no floor token in full mode
PASS: (e1) env full: floor_mode=full floor_mode_source=env tokens present
FAIL: (e2) yaml full: freepool still demoted (arm=codex kind=code model=gpt-6-astra tier=volume effort=medium reason=capability_fit chain=codex,sonnet,freepool util_glm=99 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:price_ratio,glm:capped,glm-flash:capped,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=full floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=80.0 reset_in=n/a reset_basis=unknown_window probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,freepool:1) -- 
PASS: (e2) yaml full: floor_mode=full floor_mode_source=yaml tokens present
PASS: (e3) garbage env falls through to the yaml key (bulk_only, source=yaml)
PASS: (e3) no env + no yaml key: default bulk_only, source=default
PASS: (e4) freepool_floor_mode mode=full source=env journaled by the dispatcher
FAIL: (e4) floor mode full: freepool still not picked (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.w08jBO/fp08-floor.cMAuFQ/e4-out.log) -- 
PASS: (e4b) no override: mode=bulk_only source=yaml journaled (canonical arm.yaml key)

=== 25 passed, 8 failed ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-freepool-capability-floor.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-glm-first-recovery.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.cpH0mE5sw5: Operation not permitted
mkdir: /readings: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 57: /quota-live.sh: Operation not permitted
chmod: /quota-live.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 77: /routing-gate.yaml: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 92: /routing-nogate.yaml: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 1: expected arm=glm rule=codex_quota_gate_80pct (got: arm=glm
rule=none
reason=glm_default
tier=
codex_quota_blocked=0)
[TEST] FAIL: 1: readings mismatch (got: '')
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 2: expected arm=glm with codex=91% readings (got: arm=glm
rule=none
reason=glm_default
tier=
codex_quota_blocked=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 3: expected arm=sonnet (got: arm=glm
rule=none
reason=glm_default
tier=
codex_quota_blocked=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 4: expected arm=codex rule=codex_fitting_kind, no readings (got: arm=glm
rule=none
reason=glm_default
tier=
codex_quota_blocked=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 5: expected arm=sonnet rule=safety_gate_publish_payments (got: arm=glm
rule=none
reason=glm_default
tier=
codex_quota_blocked=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 6: expected arm=sonnet (got: arm=codex
rule=none
reason=base_arm_default
tier=standard
codex_quota_blocked=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] FAIL: 7: v1 output drifted (got: $'arm=glm\nrule=none\nreason=glm_default\ntier=\ncodex_quota_blocked=0')
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 106: /calls.log: Operation not permitted
[TEST] PASS: 8: happy path -> arm=glm rule=none, no readings line, no glm/anthropic subprocess
mkdir: /repo: Operation not permitted
cp: /routing-gate.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 232: /journal.sh: Operation not permitted
chmod: /journal.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/glm.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/anthropic.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 237: /journal.log: Operation not permitted
grep: /journal.log: No such file or directory
[TEST] FAIL: 9: expected readings-carrying arm_resolved line (journal: )
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 65: /readings/codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-first-recovery.sh: line 245: /journal.log: Operation not permitted
grep: /journal.log: No such file or directory
[TEST] FAIL: 9: unexpected emit for the non-degraded path (journal: )

=== 1 passed, 10 failed ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-glm-first-recovery.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-containment.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.iKObCVOYOG: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-containment.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh (scope-selected ad-hoc)
[TEST] PASS: (a) lead_durable row + live lead pid + stale stream -> dead:silent_1801s_no_process (reclaimable)
[TEST] PASS: (a) pid_source=lead_durable recorded
[TEST] FAIL: (b) expected dead:*, got 'silent:1801' (json: {"lane":"dispatch-bbbbbbbb","verdict":"silent:1802","age_s":1802,"source":"/private/tmp/leadv2-lrsd-mG7KIS/target/docs/handoff/dispatch-bbbbbbbb/developer.stream.jsonl","log_path":"/private/tmp/leadv2-lrsd-mG7KIS/target/docs/handoff/dispatch-bbbbbbbb/developer.stream.jsonl","raw_log_path":"docs/handoff/dispatch-bbbbbbbb/developer.stream.jsonl","pid":94172,"pid_alive":true,"reason":"log_silent_process_alive","attempt":null,"child_of":null,"pid_source":"worker","pid_identity":"unverified","stream_end":"truncated"})
[TEST] FAIL: (b) pid_identity='unverified' != mismatch
[TEST] PASS: (b2) malformed birth -> unverified, lane stays silent:1801 (never dead)
[TEST] PASS: (b2) pid_identity=unverified recorded
[TEST] PASS: (c) live lane refuses the re-dispatch (rc 5)
[TEST] PASS: (c) verdict/reason/source byte-identical across the refused attempt (alive/log_fresh)
[TEST] FAIL: (c) probe-read file set changed:
before:
1788868034 21 /tmp/leadv2-lrsd-mG7KIS/target/docs/handoff/dispatch-deadlane01-architect/architect.stream.jsonl
1788868034 36 /tmp/leadv2-lrsd-mG7KIS/target/docs/handoff/dispatch-deadlane01/developer.stream.jsonl
1788868034 194 /tmp/leadv2-lrsd-mG7KIS/state/active.yaml
after:
1788868034 21 /tmp/leadv2-lrsd-mG7KIS/target/docs/handoff/dispatch-deadlane01-architect/architect.stream.jsonl
1788868034 36 /tmp/leadv2-lrsd-mG7KIS/target/docs/handoff/dispatch-deadlane01/developer.stream.jsonl
1788868040 193 /tmp/leadv2-lrsd-mG7KIS/state/active.yaml
[TEST] FAIL: (c) refusal never journaled -- attempt did not run the refusal path
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh: line 268: /bin/ps: Operation not permitted
[TEST] PASS: (d) live worker row resolves alive
[TEST] FAIL: (d) pid_source='worker' pid_identity='unverified'
[TEST] PASS: (d) live worker lane refuses the re-dispatch (rc 5)
[TEST] FAIL: (d) journal missing the lane_liveness verdict=live line
[TEST] PASS: (R2) live --all --json smoke against the real repo root parses (argv unpack in lockstep)

[LANE-REGISTRY-SELF-DEADLOCK-01] passed=9 failed=6
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh (scope-selected ad-hoc)
[CORE-OFFLINE] HERMETIC-VIOLATION (WARN, follow-up): plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh (scope-selected ad-hoc) dirtied docs/leadv2:
?? docs/leadv2/.lane-liveness-share/

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lead-worker-channel.sh (scope-selected ad-hoc)
[TEST] PASS: C1a: notify-lead exits 0 when lead is unreachable
[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct
[TEST] PASS: C1b: durable row still written for an unreachable lead
[TEST] PASS: C1c: printed SendMessage-relay line names lead=unknown
[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct
[TEST] PASS: C2a: both repos' events land in the SAME inbox for the shared lead
[TEST] PASS: C2b: rows preserve arrival order (repo A before repo B)
[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct
[TEST] PASS: C3: a second drain call returns nothing -- each row delivered exactly once
[TEST] PASS: C4: two concurrent drains delivered all 20 rows exactly once, none lost/duplicated
[TEST] FAIL: C5: undrained row missing from beat output. file: 2026-08-31T10:00:00Z [BROAD_STATUS] dispatched=0 degraded=1
| Линия | Что делает | Состояние |
|---|---|---|
| (статус не собран) | — | рендер таблицы не выполнен (render failed) |

СТАТУС НЕ СОБРАН на beat 2026-08-31T10:00:00Z: рендер таблицы не выполнен (render failed).
Таблица линий за этот beat недоступна — это НЕ значит, что линий нет.
живые линии: 0 (active.yaml не найден)
[BROAD_STATUS_END] stderr: mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.MHZCPJSpJT: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/leadv2-broad-status.sh: line 410: /render.py: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/render.py': [Errno 2] No such file or directory
[TEST] PASS: C5b: consumed row does not repeat on the next beat
[leadv2-lead-identity] WARNING: resolver unavailable or failed, falling back to direct
[TEST] PASS: C6: finished and died recorded as two distinct rows for the same lane
[TEST] PASS: C7: notifier exits 0 even when the inbox directory is unwritable
[TEST] PASS: C7b: the underlying append genuinely failed on an unwritable dir (not a vacuous pass)
[TEST] 
[TEST] === 11 passed, 1 failed ===
FAIL: C5: undrained row missing from beat output. file: 2026-08-31T10:00:00Z [BROAD_STATUS] dispatched=0 degraded=1
| Линия | Что делает | Состояние |
|---|---|---|
| (статус не собран) | — | рендер таблицы не выполнен (render failed) |

СТАТУС НЕ СОБРАН на beat 2026-08-31T10:00:00Z: рендер таблицы не выполнен (render failed).
Таблица линий за этот beat недоступна — это НЕ значит, что линий нет.
живые линии: 0 (active.yaml не найден)
[BROAD_STATUS_END] stderr: mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.MHZCPJSpJT: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/leadv2-broad-status.sh: line 410: /render.py: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/render.py': [Errno 2] No such file or directory
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lead-worker-channel.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lockout-failure-class.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.pQscW8TcmN: Operation not permitted
PASS: bash -n clean (leadv2-dispatch-code.sh)
PASS: py_compile clean (resolver + lockout-classify)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 63: /poison-glm.sh: Operation not permitted
chmod: /poison-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 63: /poison-kimi.sh: Operation not permitted
chmod: /poison-kimi.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 63: /poison-codex.sh: Operation not permitted
chmod: /poison-codex.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 63: /poison-sonnet.sh: Operation not permitted
chmod: /poison-sonnet.sh: No such file or directory
mkdir: /t1-root: Operation not permitted
mkdir: /t1-root: Operation not permitted
mkdir: /t1-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t1-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 87: /t1-glm.sh: Operation not permitted
chmod: /t1-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 99: /t1-codex.sh: Operation not permitted
chmod: /t1-codex.sh: No such file or directory
FAIL: T1: killed-worker class + duration -- lockfile=MISSING output=[leadv2-dispatch-code] lane_plan_skipped task=a694956f reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=a694956f
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=a694956f
[leadv2-dispatch-code] complexity_gate_applied task=a694956f complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=a694956f class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=a694956f reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=a694956f class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=a694956f rc=1
[leadv2-state-path] ABORT: parent of "/t1-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=a694956f rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=a694956f class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=a694956f writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=a694956f router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=a694956f router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=a694956f router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=a694956f reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=a694956f reason=protected_path
[leadv2-dispatch-code] launchable_seam task=a694956f source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=a694956f
[leadv2-dispatch-code] launchable_seam task=a694956f source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=a694956f source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=a694956f tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=a694956f reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=a694956f arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t1-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t1-cache/dispatch-ledger/.t1-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=a694956f model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=a694956f model=glm rule=none
mkdir: /t2-root: Operation not permitted
mkdir: /t2-root: Operation not permitted
mkdir: /t2-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t2-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 87: /t2-glm.sh: Operation not permitted
chmod: /t2-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 121: /t2-sonnet.sh: Operation not permitted
chmod: /t2-sonnet.sh: No such file or directory
FAIL: T2: launcher-refusal hours-scale -- lockfile=MISSING output=[leadv2-dispatch-code] lane_plan_skipped task=bc5adada reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=bc5adada
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=bc5adada
[leadv2-dispatch-code] complexity_gate_applied task=bc5adada complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=bc5adada class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=bc5adada reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=bc5adada class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=bc5adada rc=1
[leadv2-state-path] ABORT: parent of "/t2-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=bc5adada rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=bc5adada class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=bc5adada writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=bc5adada router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=bc5adada router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=bc5adada router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=bc5adada reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=bc5adada reason=protected_path
[leadv2-dispatch-code] launchable_seam task=bc5adada source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=bc5adada
[leadv2-dispatch-code] launchable_seam task=bc5adada source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=bc5adada source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=bc5adada tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=bc5adada reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=bc5adada arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t2-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t2-cache/dispatch-ledger/.t2-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=bc5adada model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=bc5adada model=glm rule=none
mkdir: /t3-root: Operation not permitted
mkdir: /t3-root: Operation not permitted
mkdir: /t3-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t3-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 87: /t3-glm.sh: Operation not permitted
chmod: /t3-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 99: /t3-codex.sh: Operation not permitted
chmod: /t3-codex.sh: No such file or directory
FAIL: T3: post-spawn cap clamp -- lockfile=MISSING output=[leadv2-dispatch-code] lane_plan_skipped task=4aabe789 reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=4aabe789
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=4aabe789
[leadv2-dispatch-code] complexity_gate_applied task=4aabe789 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=4aabe789 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=4aabe789 reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=4aabe789 class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=4aabe789 rc=1
[leadv2-state-path] ABORT: parent of "/t3-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=4aabe789 rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=4aabe789 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=4aabe789 writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=4aabe789 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=4aabe789 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=4aabe789 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=4aabe789 reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=4aabe789 reason=protected_path
[leadv2-dispatch-code] launchable_seam task=4aabe789 source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=4aabe789
[leadv2-dispatch-code] launchable_seam task=4aabe789 source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=4aabe789 source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=4aabe789 tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=4aabe789 reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=4aabe789 arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t3-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t3-cache/dispatch-ledger/.t3-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=4aabe789 model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=4aabe789 model=glm rule=none
mkdir: /t4-root: Operation not permitted
mkdir: /t4-root: Operation not permitted
mkdir: /t4-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t4-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 87: /t4-glm.sh: Operation not permitted
chmod: /t4-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 121: /t4-sonnet.sh: Operation not permitted
chmod: /t4-sonnet.sh: No such file or directory
mkdir: /t4-lockout: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 275: /t4-lockout/quota-lockout-glm.json: No such file or directory
FAIL: T4a: expired record, bash path -- rc=1 output=[leadv2-dispatch-code] lane_plan_skipped task=7fe83403 reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=7fe83403
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=7fe83403
[leadv2-dispatch-code] complexity_gate_applied task=7fe83403 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=7fe83403 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=7fe83403 reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=7fe83403 class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=7fe83403 rc=1
[leadv2-state-path] ABORT: parent of "/t4-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=7fe83403 rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=7fe83403 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=7fe83403 writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=7fe83403 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=7fe83403 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=7fe83403 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=7fe83403 reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=7fe83403 reason=protected_path
[leadv2-dispatch-code] launchable_seam task=7fe83403 source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=7fe83403
[leadv2-dispatch-code] launchable_seam task=7fe83403 source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=7fe83403 source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=7fe83403 tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=7fe83403 reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=7fe83403 arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t4-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t4-cache/dispatch-ledger/.t4-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=7fe83403 model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=7fe83403 model=glm rule=none
mkdir: /t4-lockout-py: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 299: /t4-lockout-py/quota-lockout-codex.json: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 137: /t4-quota-live.sh: Operation not permitted
chmod: /t4-quota-live.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 147: /t4-kimi.sh: Operation not permitted
chmod: /t4-kimi.sh: No such file or directory
PASS: T4b: expired codex record — resolver (_lockout_blocked) does not block codex
mkdir: /t5-root: Operation not permitted
mkdir: /t5-root: Operation not permitted
mkdir: /t5-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t5-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 87: /t5-glm.sh: Operation not permitted
chmod: /t5-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 121: /t5-sonnet.sh: Operation not permitted
chmod: /t5-sonnet.sh: No such file or directory
mkdir: /t5-lockout: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 322: /t5-lockout/quota-lockout-glm.json: No such file or directory
FAIL: T5a: malformed record, bash path -- rc=1 output=[leadv2-dispatch-code] lane_plan_skipped task=863e863a reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=863e863a
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=863e863a
[leadv2-dispatch-code] complexity_gate_applied task=863e863a complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=863e863a class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=863e863a reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=863e863a class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=863e863a rc=1
[leadv2-state-path] ABORT: parent of "/t5-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=863e863a rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=863e863a class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=863e863a writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=863e863a router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=863e863a router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=863e863a router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=863e863a reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=863e863a reason=protected_path
[leadv2-dispatch-code] launchable_seam task=863e863a source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=863e863a
[leadv2-dispatch-code] launchable_seam task=863e863a source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=863e863a source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=863e863a tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=863e863a reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=863e863a arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t5-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t5-cache/dispatch-ledger/.t5-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=863e863a model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=863e863a model=glm rule=none
mkdir: /t5-lockout-py: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 340: /t5-lockout-py/quota-lockout-codex.json: No such file or directory
PASS: T5b: malformed codex record — resolver exits 0, codex not lockout-blocked
mkdir: /t6-root: Operation not permitted
mkdir: /t6-root: Operation not permitted
mkdir: /t6-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t6-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 87: /t6-glm.sh: Operation not permitted
chmod: /t6-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 99: /t6-codex.sh: Operation not permitted
chmod: /t6-codex.sh: No such file or directory
FAIL: T6: ordinary failure must not lock out -- lockfile_exists=no output=[leadv2-dispatch-code] lane_plan_skipped task=580139e2 reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=580139e2
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=580139e2
[leadv2-dispatch-code] complexity_gate_applied task=580139e2 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=580139e2 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=580139e2 reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=580139e2 class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=580139e2 rc=1
[leadv2-state-path] ABORT: parent of "/t6-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=580139e2 rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=580139e2 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=580139e2 writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=580139e2 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=580139e2 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=580139e2 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=580139e2 reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=580139e2 reason=protected_path
[leadv2-dispatch-code] launchable_seam task=580139e2 source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=580139e2
[leadv2-dispatch-code] launchable_seam task=580139e2 source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=580139e2 source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=580139e2 tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=580139e2 reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=580139e2 arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t6-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t6-cache/dispatch-ledger/.t6-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=580139e2 model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=580139e2 model=glm rule=none
mkdir: /t7-root: Operation not permitted
mkdir: /t7-root: Operation not permitted
mkdir: /t7-root: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 76: /t7-root/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 121: /t7-sonnet.sh: Operation not permitted
chmod: /t7-sonnet.sh: No such file or directory
mkdir: /t7-lockout: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 380: /t7-lockout/quota-lockout-glm.json: No such file or directory
FAIL: T7: bench banner -- banner_line=none route_line=13 output=[leadv2-dispatch-code] lane_plan_skipped task=51505f32 reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=51505f32
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=51505f32
[leadv2-dispatch-code] complexity_gate_applied task=51505f32 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=51505f32 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=51505f32 reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=51505f32 class=non_product reason=explicit_mission_fast_path kind=unknown
[leadv2-dispatch-code] active_register_miss task=51505f32 rc=1
[leadv2-state-path] ABORT: parent of "/t7-root/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=51505f32 rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=51505f32 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] protection_derived by=router task=51505f32 writes=<none> write_class=unknown writes_protected=1 manual_protected=0 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=haiku task=51505f32 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=opus task=51505f32 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_dropped_not_dispatchable arm=fable task=51505f32 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=51505f32 reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=51505f32 reason=protected_path
[leadv2-dispatch-code] launchable_seam task=51505f32 source=registry kind=code
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=51505f32
[leadv2-dispatch-code] launchable_seam task=51505f32 source=registry kind=code
[leadv2-dispatch-code] launchable_seam task=51505f32 source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=51505f32 tail=glm-flash,freepool
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=51505f32 reason=cheapest_capable arbiter_pick=glm util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[leadv2-dispatch-code] candidate_chain task=51505f32 arms=glm,codex,sonnet,glm-flash,freepool
mkdir: /t7-cache: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/../leadv2-dispatch-code.sh: line 3796: /t7-cache/dispatch-ledger/.t7-root.dispatch.lock: No such file or directory
[leadv2-dispatch-code] ERROR: dispatch reservation FAILED for task=51505f32 model=glm -- ledger write did not land (read-only/full fs?); refusing to spawn
[leadv2-dispatch-code] dispatch_reservation_failed task=51505f32 model=glm rule=none
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lockout-failure-class.sh: line 99: /t8-codex.sh: Operation not permitted
chmod: /t8-codex.sh: No such file or directory
FAIL: T8: strikes escalation -- lockfile=MISSING run1=[leadv2-dispatch-code] arm_postspawn_verdict arm=codex state=failed quota=no task=-
[leadv2-dispatch-code] arm_failure_classified arm=codex site=postspawn class=unclassified evidence=none lockout=none task=- run2=[leadv2-dispatch-code] arm_postspawn_verdict arm=codex state=failed quota=no task=-
[leadv2-dispatch-code] arm_failure_classified arm=codex site=postspawn class=unclassified evidence=none lockout=none task=-
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lockout-failure-class.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh (scope-selected ad-hoc)
test: 1 new Standard dispatch without plan/gate1 is refused before spawn
test: 2 approved new Standard dispatch is admitted
test: 3 resumed approved Standard lane is admitted
test: 4 caller bootstrap claim cannot override the recorded store
test: 5 project-root mismatch fails loudly and PROJECT_ROOT alone is honoured
test: 5c cross-repo record (cwd repo != LEADV2_PROJECT_ROOT repo, no dispatch dir) is refused, creates nothing
test: 5d same-repo first record with no dispatch dir yet is permitted (fresh-dispatch shape)

[PHASE-GATE-INVERSION] pass=18 fail=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-plan-in-lane.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.ZVrOaATsrg: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-plan-in-lane.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.XtRBon6UPs: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh: line 52: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh: line 53: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh: line 56: /worker: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh: line 60: /architect_slow: Operation not permitted
chmod: /worker: No such file or directory
chmod: /architect_slow: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh: line 68: /out.log: Operation not permitted
grep: /out.log: No such file or directory
[FAIL] check1: expected 'architect_prepass status=failed reason=timeout rc=124' in dispatch output
tail: /out.log: No such file or directory
[ok] check2: historical journal fixtures match the population split (where present)
=== 1 check(s) FAILED ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-route-arbiter.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.oF2dsMwOdY: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-route-arbiter.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-spawn-handle-parse.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/kimi-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: dep floor: python3
[TEST] PASS: (a) launcher prints a non-empty handle with no path prefix (260908-145119-repo-692b)
[TEST] PASS: (b) the launcher line is a single copy, not handle+handle (the halving assumption was false)
[TEST] PASS: extracted the production handle assignment from the kimi case block
[TEST] PASS: (c) the production parser returns the launcher's handle unchanged
[TEST] PASS: (c2) status resolves the parsed handle — it names a real run
[TEST] PASS: (d) [260906-101112-repo-abcd] passes through whole
[TEST] PASS: (d) [odd-length-handle-123] passes through whole
[TEST] PASS: (d) [dup-dup] passes through whole
mutation applied
[TEST] PASS: (e) NEG-CTL: with the halving back, the parser truncates to [260906-1011] — cases (c)/(d) would go RED
[TEST] test-spawn-handle-parse: 12 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/freepool-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/kimi-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-codex-planner.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/lib/leadv2-worker-mcp.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/codex-task.sh (bash 5, /bin/bash 3.2 leg skipped — pre-existing heredoc false positive)
[TEST] PASS: freepool-coder.sh run: --mcp-config on argv (default LEADV2_WORKER_MCP=1)
[TEST] PASS: freepool-coder.sh run: resolved config carries both servers
[TEST] PASS: freepool-coder.sh run: LEADV2_WORKER_MCP=0 must NOT attach --mcp-config
[TEST] PASS: kimi-coder.sh run: --mcp-config on argv (default LEADV2_WORKER_MCP=1)
[TEST] PASS: kimi-coder.sh run: resolved config carries both servers
[TEST] PASS: freepool bg: run finalized (run_id=260908-145129-fp-bg-repo-7a0a)
[TEST] PASS: freepool bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv
[TEST] PASS: freepool bg: role-resolved config with both servers reaches the child (--mcp-config value)
[TEST] PASS: freepool bg: child env carries the transport (BASE_URL/AUTH_TOKEN) + FREEPOOL_ROLE
[TEST] PASS: freepool bg: code-intel preamble + mission both inside the child -p prompt
[TEST] PASS: kimi bg: run finalized (run_id=260908-145132-kimi-bg-repo-53ab)
[TEST] FAIL: kimi bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv
[TEST] FAIL: kimi bg: role-resolved config with both servers reaches the child (--mcp-config value)
[TEST] FAIL: kimi bg: child env carries the transport (BASE_URL/AUTH_TOKEN)
[TEST] FAIL: kimi bg: code-intel preamble + mission both inside the child -p prompt
[TEST] FAIL: kimi bg: journal keeps BOTH the pre-spawn worker_mcp_attached record and the stream (tee -a); got: [2026-09-08 14:51:33] worker_mcp_attached config=mcp-role-developer.resolved.json role=developer|
[TEST] PASS: config/codex-mcp-servers.toml declares both server names
[TEST] PASS: codex-task.sh emits documented MCP-gap NOTE
[TEST] PASS: worker-code-intel-preamble.md exists
[TEST] PASS: worker-code-intel-preamble.md <= 25 lines (      16)
[TEST] PASS: worker-code-intel-preamble.md covers graph/repowise/distill routing
[TEST] PASS: preamble gate: kimi attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: freepool attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: glm attached (default gate) -> rc=0 + preamble text
[TEST] PASS: preamble gate: kimi LEADV2_WORKER_MCP=0 -> rc=3 + empty output
[TEST] PASS: preamble gate: kimi fail-open (nothing resolvable) -> rc=3 + empty output
[TEST] PASS: preamble gate: codex unwired -> rc=4 + empty output
[TEST] PASS: preamble gate: sonnet default (no SLIM_MCP) -> rc=3 + empty output
[TEST] PASS: preamble gate: sonnet LEADV2_SUBSESSION_SLIM_MCP=1 -> rc=0 + preamble text
[TEST] PASS: preamble gate: fail-open branch stays silent (no inverted 'MCP unavailable' claim)
[TEST] PASS: leadv2-dispatch-code.sh: preamble injection is gated by worker_mcp_preamble_for_arm(arm)
[TEST] PASS: leadv2-dispatch-code.sh: unconditional-injection marker _LEADV2_CODE_INTEL_PREAMBLE stays deleted (round-2 H2 regression)
[TEST] PASS: leadv2-dispatch-code.sh: sources the shared worker-MCP lib (no second resolver)
[leadv2-dispatch-code] code_intel_preamble arm=kimi task=wiretest8 mode=attached
[leadv2-dispatch-code] effort_dropped by=router arm=kimi task=wiretest8 effort=high reason=no_effort_control
[leadv2-dispatch-code] worker_spawned by=router model=kimi task=wiretest8 attempt=wiretest8-1788868296-22821 handle=wmbh8wmbh8
worker_spawned model=kimi task=wiretest8 attempt=wiretest8-1788868296-22821 handle=wmbh8wmbh8
[leadv2-dispatch-code] mission-version task=- sig=wiretest8 rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
[TEST] PASS: leadv2-dispatch-code.sh: _spawn_worker_body puts the resolved preamble text INSIDE the mission the child bg call receives
[TEST] negative control (mission fold): structural dispatch_gate_check still PASSES on the mutant, as predicted (R4 finding 2) -- the behavioural case below must be the one that catches it
[leadv2-dispatch-code] code_intel_preamble arm=kimi task=wiretest8 mode=skipped reason=fail_open cause=resolve_role_mcp_config_rc=11
[leadv2-dispatch-code] effort_dropped by=router arm=kimi task=wiretest8 effort=high reason=no_effort_control
[leadv2-dispatch-code] worker_spawned by=router model=kimi task=wiretest8 attempt=wiretest8-1788868299-24048 handle=wmbh8wmbh8
worker_spawned model=kimi task=wiretest8 attempt=wiretest8-1788868299-24048 handle=wmbh8wmbh8
[leadv2-dispatch-code] mission-version task=- sig=wiretest8 rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
[TEST] PASS: negative control (mission fold): mutated dispatcher goes RED -- preamble text absent from the mission the child receives (mutation caught)
[TEST] PASS: negative control: mutation applied to scratch copy
[TEST] PASS: negative control: mutated freepool-coder.sh correctly goes RED (no --mcp-config)
[TEST] PASS: negative control (freepool-bg): mutated bg run finalized
[TEST] PASS: negative control (freepool-bg): mutated cmd_run_child goes RED (no --mcp-config reaches the child)
[TEST] PASS: negative control (kimi-bg): mutated bg run finalized
[TEST] PASS: negative control (kimi-bg): mutated cmd_run_child goes RED (no --mcp-config reaches the child)
[TEST] PASS: negative control (tee -a): mutated kimi goes RED — attached record destroyed by truncation, journal case catches it
[TEST] PASS: negative control (dispatch gate): unconditional injection goes RED — dispatch gate check catches it

[TEST] TOTAL: PASS=44 FAIL=5
[TEST] FAIL: kimi bg: cmd_run_child puts --strict-mcp-config --mcp-config on the child argv
[TEST] FAIL: kimi bg: role-resolved config with both servers reaches the child (--mcp-config value)
[TEST] FAIL: kimi bg: child env carries the transport (BASE_URL/AUTH_TOKEN)
[TEST] FAIL: kimi bg: code-intel preamble + mission both inside the child -p prompt
[TEST] FAIL: kimi bg: journal keeps BOTH the pre-spawn worker_mcp_attached record and the stream (tee -a); got: [2026-09-08 14:51:33] worker_mcp_attached config=mcp-role-developer.resolved.json role=developer|
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/tests/test-arm-pool-reachability.sh (scope-selected ad-hoc)
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
```

### Evidence: changed-scope core shard 1, partial raw output

```text

[CORE-OFFLINE] lane placement pin (--resume-lane/--worktree)
[TEST] PASS: P-a: dispatch exited 0
[TEST] PASS: P-a: worker cwd == RESUME-ME-01 worktree
[TEST] FAIL: P-h(a): prompt pin line MISSING with --resume-lane
[TEST] PASS: P-b: dispatch exited 0
[TEST] PASS: P-b: worker cwd == RESUME-ME-01 worktree (via --worktree)
[TEST] FAIL: P-h(b): prompt pin line MISSING with --worktree
[TEST] PASS: P-c: dispatch exited 5 (placement refused)
[TEST] PASS: P-c: stderr contains REFUSE placement line
[TEST] PASS: P-c: no worker spawned (no cwd recorded)
[TEST] PASS: P-c: no reservation ledger row for this dispatch
[TEST] PASS: P-d: dispatch exited 5 (foreign repo refused)
[TEST] PASS: P-d: stderr contains foreign_repo reason
[TEST] PASS: P-d: no worker spawned
[TEST] PASS: P-e: dispatch exited 5 (live lane refused)
[TEST] PASS: P-e: stderr contains lane_is_live reason
[TEST] PASS: P-e: no worker spawned
[TEST] PASS: P-f: dispatch exited 1 (usage error for both flags)
[TEST] PASS: P-f: no worker spawned
[TEST] PASS: P-g: dispatch exited 0 (no flag, regression)
[TEST] PASS: P-g: worker cwd is a fresh tree, != RESUME-ME-01
[TEST] FAIL: P-h(g): prompt pin line MISSING on default ensure-created path
[TEST] FAIL: P-h(g2): pin line does NOT name the worktree (expected '/tmp/leadv2-lpp-MZZIR0/target/.claude/worktrees/50e51359')
[TEST] PASS: D3: ensure-created lane receives context.yaml without --worktree
[TEST] PASS: D3: worker mission references the lane-local plan
[TEST] PASS: P-i: dispatch exited 0 (shared-tree fallback)
[TEST] PASS: P-i: no pin line on shared-tree dispatch
[TEST] PASS: contract: leadv2-lane-liveness.sh --json emits a JSON object with verdict/reason/age_s

[LANE-PLACEMENT-01] passed=23 failed=4
[CORE-OFFLINE] FAILED: lane placement pin (--resume-lane/--worktree)

[CORE-OFFLINE] phase precondition guard matrix
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.mUI0Anw45I: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition.sh: line 80: /journal.sh: Operation not permitted
chmod: /journal.sh: No such file or directory
test: Standard missing plan/gate1
test: waiver review refused
test: waiver close refused
test: waiver empty reason
test: phases.yaml version 2 rejected
mkdir: /.claude: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition.sh: line 147: /.claude/leadv2-overrides/phases.yaml: No such file or directory
missing=classify,plan,gate1,build,test,review,live_verify,close
required=classify,plan,gate1,build,test,review,live_verify,close
unmet=classify,plan,gate1,build,test,review,live_verify,close
  FAIL: version 2 should exit 4 (got 3)
test: phases.yaml removal key rejected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition.sh: line 157: /.claude/leadv2-overrides/phases.yaml: No such file or directory
  FAIL: remove key should exit 4 (got 3)
  FAIL: error should name removals
test: phases.yaml union adds e2e to Light
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition.sh: line 178: /.claude/leadv2-overrides/phases.yaml: No such file or directory
  FAIL: Light + override should make e2e mandatory
test: waiver plan accepted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition.sh: line 194: /.claude/leadv2-overrides/phases.yaml: No such file or directory
  FAIL: accepted waiver should not exit 4 (got 4)
  FAIL: waived plan.yaml not written
test: waiver plan not allowed
test: no phases.yaml → base table

test: G1 REQUIRE_PHASES unset warns and spawns
  FAIL: G1: journal should contain phase_precondition_warn
test: G2 REQUIRE_PHASES=1 refuses and does not spawn
  FAIL: G2: dispatch should exit 3 (got 0)
  FAIL: G2: spawn sentinel should NOT exist
  FAIL: G2: journal should contain phase_precondition_refused
test: G3 REQUIRE_PHASES=0 no warn and spawns
test: G4 phase-waiver review refused in modes unset/1 (0 proceeds, see G8)
test: G5 forged review diff_hash rejected
test: G6 artifact integrity rejected
test: G7 review provenance — de-self-attestation
test: G8 REQUIRE_PHASES=0 proceeds despite broken phases.yaml + refused waiver
test: G9 deploy descendant-of-lane-base
test: G10 PROOF column — self-attested vs verified vs unverified
test: G11 unexpected assert exit code (B4)
test: F1 record refuses an unprovable artifact, and still stamps unverified when the evidence merely has not landed yet
test: F2 plan-for --writes makes deploy mandatory
test: F3 plan-for rejects invalid class
MANDATORY classify
MANDATORY build
NA test docs_only
MANDATORY review
NA deploy no_runtime_surface
MANDATORY close
MANDATORY classify
OPTIONAL plan
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
NA live_verify no_deploy
MANDATORY close
MANDATORY classify
OPTIONAL diverge
MANDATORY plan
MANDATORY gate1
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
MANDATORY live_verify
NA e2e no_deploy
MANDATORY close
MANDATORY classify
MANDATORY diverge
MANDATORY plan
MANDATORY gate1
MANDATORY build
MANDATORY test
MANDATORY review
NA deploy no_runtime_surface
MANDATORY live_verify
MANDATORY e2e
MANDATORY close

[PHASE-PRECONDITION] pass=72 fail=10
[CORE-OFFLINE] FAILED: phase precondition guard matrix

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-admission-safety-pin.sh (scope-selected ad-hoc)
PASS: bash syntax: dispatch
PASS: (green) judge-only safety signal, no --safety flag -- pin fires
PASS: (green) pin reaches routing enforcement, not just the admission journal
PASS: (baseline) risk_class=none -- no safety_pin_applied line
PASS: (red) with the fold-in stripped, the second door reopens -- no safety_pin_applied line
PASS: (red) no safety enforcement in routing -- exact pre-fix symptom reproduced
---
PASS=6 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.kVYttXJ23q: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh: line 41: /poison-glm.sh: Operation not permitted
chmod: /poison-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh: line 41: /poison-kimi.sh: Operation not permitted
chmod: /poison-kimi.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh: line 41: /poison-codex.sh: Operation not permitted
chmod: /poison-codex.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh: line 41: /poison-subsession.sh: Operation not permitted
chmod: /poison-subsession.sh: No such file or directory
PASS: case1: legacy fallback list (glm codex sonnet) ⊆ DISPATCHABLE_BUILD_ARMS (codex freepool glm glm-flash sonnet)
FAIL: case2: yaml ladder has 'haiku' not in DISPATCHABLE_BUILD_ARMS (codex freepool glm glm-flash sonnet)
PASS: case3a: kimi absent from legacy fallback list
PASS: case3b: kimi absent from yaml-loaded ladder
PASS: case4: router_v2.arms (normalized:  glm glm-flash freepool codex haiku sonnet opus) ⊆ DISPATCHABLE_BUILD_ARMS ∪ advisory; kimi absent
FAIL: case5: v1/v2 divergence -- v1=(codex fable freepool glm glm-flash haiku opus sonnet ) v2=(codex freepool glm glm-flash sonnet )
PASS: case6: _dispatchable_arms() fail-open fallback (glm codex sonnet) ⊆ DISPATCHABLE_BUILD_ARMS; kimi absent
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.leFE2V6WUE: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh: line 252: /run.sh: Operation not permitted
chmod: /run.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh: line 255: /stderr.log: Operation not permitted
cat: /stderr.log: No such file or directory
FAIL: case7: empty stdout (no fallback returned)

================================================
  arm-ladder vocabulary-drift suite: PASS=5 FAIL=3
================================================
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.8Ej4aigo8J: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-class-floor-survives-resume.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-complexity-routing.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.p1AgLaRewe: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-complexity-routing.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.gc3fLYwmwl: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh: line 26: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh: line 27: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh: line 30: /worker: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh: line 31: /architect: Operation not permitted
chmod: /worker: No such file or directory
chmod: /architect: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh: line 47: /out.log: Operation not permitted
grep: /out.log: No such file or directory
FAIL no architect_prepass timeout was ever journaled: elapsed=0s
cat: /out.log: No such file or directory
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh (scope-selected ad-hoc)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=4985f7ec status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=4985f7ec reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/4985f7ec/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=4985f7ec
[leadv2-dispatch-code] complexity_gate_applied task=4985f7ec complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=4985f7ec class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=4985f7ec founder_task=4985f7ec complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/4985f7ec/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=4985f7ec class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=4985f7ec class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=4985f7ec status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=4985f7ec status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=4985f7ec status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=4985f7ec status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=4985f7ec status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=4985f7ec founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=4985f7ec after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=4985f7ec id=dispatch-4985f7ec where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 1: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=12713ac2 status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=12713ac2 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/12713ac2/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=12713ac2
[leadv2-dispatch-code] complexity_gate_applied task=12713ac2 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=12713ac2 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=12713ac2 founder_task=12713ac2 complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/12713ac2/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=12713ac2 class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=12713ac2 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=12713ac2 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=12713ac2 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=12713ac2 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=12713ac2 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=12713ac2 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=12713ac2 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=12713ac2 after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=12713ac2 id=dispatch-12713ac2 where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 2: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=87a8ee13 status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=87a8ee13 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/87a8ee13/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=87a8ee13
[leadv2-dispatch-code] complexity_gate_applied task=87a8ee13 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=87a8ee13 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=87a8ee13 founder_task=87a8ee13 complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/87a8ee13/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=87a8ee13 class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=87a8ee13 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=87a8ee13 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=87a8ee13 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=87a8ee13 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=87a8ee13 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=87a8ee13 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=87a8ee13 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=87a8ee13 after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=87a8ee13 id=dispatch-87a8ee13 where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 3: setup — first dispatch failed or fake process died too fast (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=6bfd8cb3 status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=6bfd8cb3 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/6bfd8cb3/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=6bfd8cb3
[leadv2-dispatch-code] complexity_gate_applied task=6bfd8cb3 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=6bfd8cb3 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=6bfd8cb3 founder_task=6bfd8cb3 complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/6bfd8cb3/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=6bfd8cb3 class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=6bfd8cb3 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=6bfd8cb3 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=6bfd8cb3 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=6bfd8cb3 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=6bfd8cb3 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=6bfd8cb3 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=6bfd8cb3 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=6bfd8cb3 after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=6bfd8cb3 id=dispatch-6bfd8cb3 where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 4: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=0a6f2efb status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=0a6f2efb reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/0a6f2efb/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=0a6f2efb
[leadv2-dispatch-code] complexity_gate_applied task=0a6f2efb complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=0a6f2efb class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=0a6f2efb founder_task=0a6f2efb complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/0a6f2efb/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=0a6f2efb class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=0a6f2efb class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=0a6f2efb status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=0a6f2efb status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=0a6f2efb status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=0a6f2efb status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=0a6f2efb status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=0a6f2efb founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=0a6f2efb after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=0a6f2efb id=dispatch-0a6f2efb where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 5: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=7b7da47a status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=7b7da47a reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/7b7da47a/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=7b7da47a
[leadv2-dispatch-code] complexity_gate_applied task=7b7da47a complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=7b7da47a class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=7b7da47a founder_task=7b7da47a complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/7b7da47a/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=7b7da47a class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=7b7da47a class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=7b7da47a status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=7b7da47a status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7b7da47a status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=7b7da47a status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7b7da47a status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=7b7da47a founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=7b7da47a after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=7b7da47a id=dispatch-7b7da47a where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 6: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=0ab414ba status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=0ab414ba reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/0ab414ba/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=0ab414ba
[leadv2-dispatch-code] complexity_gate_applied task=0ab414ba complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=0ab414ba class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=0ab414ba founder_task=0ab414ba complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/0ab414ba/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=0ab414ba class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=0ab414ba class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=0ab414ba status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=0ab414ba status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=0ab414ba status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=0ab414ba status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=0ab414ba status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=0ab414ba founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=0ab414ba after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=0ab414ba id=dispatch-0ab414ba where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 7/missing: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=be702adb status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.T641e5/dispatch-partial-close-2916-1788867807.1NwJNZ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=be702adb reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/be702adb/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=be702adb
[leadv2-dispatch-code] complexity_gate_applied task=be702adb complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=be702adb class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=be702adb founder_task=be702adb complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/be702adb/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=be702adb class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=be702adb class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=be702adb status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=be702adb status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=be702adb status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=be702adb status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=be702adb status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=be702adb founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=be702adb after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=be702adb id=dispatch-be702adb where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 7/malformed: setup — first dispatch or process-death wait failed (rc=3)

[TEST] 0 passed, 8 failed
[TEST] Failures:
  - 1: setup — first dispatch or process-death wait failed (rc=3)
  - 2: setup — first dispatch or process-death wait failed (rc=3)
  - 3: setup — first dispatch failed or fake process died too fast (rc=3)
  - 4: setup — first dispatch or process-death wait failed (rc=3)
  - 5: setup — first dispatch or process-death wait failed (rc=3)
  - 6: setup — first dispatch or process-death wait failed (rc=3)
  - 7/missing: setup — first dispatch or process-death wait failed (rc=3)
  - 7/malformed: setup — first dispatch or process-death wait failed (rc=3)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh (scope-selected ad-hoc)
[CORE-OFFLINE] HERMETIC-VIOLATION (WARN, follow-up): plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh (scope-selected ad-hoc) dirtied docs/leadv2:
?? docs/leadv2/.lane-liveness-share/

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh (scope-selected ad-hoc)

=== S7: --resume-lane on finalized lane → accepted ===
[TEST] PASS: S7-pre: liveness probe returns dead:sentinel_finalized
[TEST] PASS: S7: dispatch resumed the finalized lane (rc=0)
[TEST] PASS: S7: no lane_is_live in stderr
[TEST] PASS: S7: placement was pinned (accepted)

=== Results: 4 passed, 0 failed ===

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-fable-think-tier.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.L56NaJGMDI: Operation not permitted
PASS: resolver default = fable
PASS: resolver LEADV2_THINK_MODEL=opus override wins (negative control)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 80: /cap-unavailable.yaml: Operation not permitted
PASS: resolver falls back to opus when fable marked unavailable
PASS: kill switch beats env: LEADV2_THINK_MODEL=fable + fable unavailable -> 'opus' (never fable)
PASS: dispatch export path runs under set -u even with a pre-set pin; spawned child sees resolver's answer LEADV2_THINK_MODEL=opus (kill switch overwrote the 'fable' pin)
PASS: file order: SCRIPT_DIR assignment (line 483) precedes export block (line 495)
FAIL: tree-wide census: unclassified 'opus' literal(s): /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.75882.sh:3609:  out="$(PROJECT_ROOT="${PROJECT_ROOT}" python3 - "${ARCHITECT_PREPASS_TIMEOUT_SEC}" "${ARCHITECT_BIN}" "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" "dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}" "${mfile}" <<'PY' 2>&1
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.75882.sh:3701:    case "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" in
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.75882.sh:3703:      *) _pp_failed_prov="$(_arm_provider "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}")" ;;
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.75882.sh:4944:                Exit codes: 0 spawned/resolved, 2 duplicate task-sig, 3 arm=opus (lead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.75882.sh:5640:  if [[ "${arm}" == "opus" ]]; then
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.dbg-funcs.sh:3606:  out="$(PROJECT_ROOT="${PROJECT_ROOT}" python3 - "${ARCHITECT_PREPASS_TIMEOUT_SEC}" "${ARCHITECT_BIN}" "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" "dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}" "${mfile}" <<'PY' 2>&1
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.dbg-funcs.sh:3698:    case "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" in
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.dbg-funcs.sh:3700:      *) _pp_failed_prov="$(_arm_provider "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}")" ;;
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.dbg-funcs.sh:4941:                Exit codes: 0 spawned/resolved, 2 duplicate task-sig, 3 arm=opus (lead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.dbg-funcs.sh:5634:  if [[ "${arm}" == "opus" ]]; then
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.59126.sh:3609:  out="$(PROJECT_ROOT="${PROJECT_ROOT}" python3 - "${ARCHITECT_PREPASS_TIMEOUT_SEC}" "${ARCHITECT_BIN}" "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" "dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}" "${mfile}" <<'PY' 2>&1
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.59126.sh:3701:    case "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" in
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.59126.sh:3703:      *) _pp_failed_prov="$(_arm_provider "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}")" ;;
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.59126.sh:4944:                Exit codes: 0 spawned/resolved, 2 duplicate task-sig, 3 arm=opus (lead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.59126.sh:5640:  if [[ "${arm}" == "opus" ]]; then
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/lib/leadv2-launch-registry.py:131:                {"codex", "sonnet", "opus", "fable"})
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/lib/leadv2-launch-registry.py:246:_CLAUDE_ARMS = ("haiku", "sonnet", "opus", "fable")
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.68797.sh:3609:  out="$(PROJECT_ROOT="${PROJECT_ROOT}" python3 - "${ARCHITECT_PREPASS_TIMEOUT_SEC}" "${ARCHITECT_BIN}" "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" "dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}" "${mfile}" <<'PY' 2>&1
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.68797.sh:3701:    case "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" in
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.68797.sh:3703:      *) _pp_failed_prov="$(_arm_provider "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}")" ;;
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.68797.sh:4944:                Exit codes: 0 spawned/resolved, 2 duplicate task-sig, 3 arm=opus (lead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.68797.sh:5640:  if [[ "${arm}" == "opus" ]]; then
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.63162.sh:3609:  out="$(PROJECT_ROOT="${PROJECT_ROOT}" python3 - "${ARCHITECT_PREPASS_TIMEOUT_SEC}" "${ARCHITECT_BIN}" "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" "dispatch-${sig8}-${ARCHITECT_LANE_SUFFIX}" "${mfile}" <<'PY' 2>&1
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.63162.sh:3701:    case "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}" in
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.63162.sh:3703:      *) _pp_failed_prov="$(_arm_provider "${LEADV2_DISPATCH_ARCHITECT_MODEL:-opus}")" ;;
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.63162.sh:4944:                Exit codes: 0 spawned/resolved, 2 duplicate task-sig, 3 arm=opus (lead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/.test-dispatch-ppf-r5-funcs.63162.sh:5640:  if [[ "${arm}" == "opus" ]]; then
PASS: repo-install.sh: LEADV2_MAIN_MODEL has its own default (opus), independent of LV2_THINK_MODEL —  "LEADV2_MAIN_MODEL": os.environ.get("LV2_MAIN_MODEL", "opus"),
PASS: repo-install.sh: LEADV2_THINK_MODEL still resolves via the think resolver (fable), independent of the main axis —  "LEADV2_THINK_MODEL": os.environ.get("LV2_THINK_MODEL", "fable"),
PASS: negative control A: pre-fix collapsed main-axis line correctly RED under the split check; the real file's line above is GREEN (revert proven)
PASS: negative control B: a main-derived think-axis line correctly RED under the split check; the real file's line above is GREEN (revert proven)
PASS: mutation A (full model id pin) matches census_re
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 388: /mut-fallback-no-guard.js: Operation not permitted
PASS: mutation B (unguarded 'fallback'-labeled opus pin) correctly rejected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 399: /mut-fallback-guard.js: Operation not permitted
FAIL: resolver-gated fallback (guard present) wrongly rejected
fixtures 2d: red-shapes+controls matched=10 missed=0
mkdir: /stub-repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 449: /stub-repo/.claude/leadv2-overrides/session-routing.yaml: No such file or directory
PASS: session-route Heavy: stub config 'heavy: opus' cannot pin — resolver wins (model=fable)
PASS: session-route Heavy: unreachable resolver degrades to fable, script survives (rc=0)
PASS: leadv2-diverge: THINK_MODEL honours LEADV2_THINK_MODEL env (kill-switch channel)
PASS: leadv2-learn: THINK_MODEL honours LEADV2_THINK_MODEL env (kill-switch channel)
PASS: leadv2-diagnose: THINK_MODEL honours LEADV2_THINK_MODEL env (kill-switch channel)
PASS: leadv2-po-feedback-loop: THINK_MODEL honours LEADV2_THINK_MODEL env (kill-switch channel)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 495: /ask-model-stub.sh: Operation not permitted
chmod: /ask-model-stub.sh: No such file or directory
mkdir: /ask-repo: Operation not permitted
mkdir: /ask-repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 514: /ask-repo/docs/tasks.yaml: No such file or directory
FAIL: ask architect-decide: expected timeout->architect with --model fable; got qfile=<none> decision=none
PASS: llm-judge: resolver command substitution failure-guarded (set -euo pipefail safe)
PASS: repo-install: LEADV2_THINK_MODEL written into settings.json env (kill-switch channel)
PASS: dispatch-code: unconditional LEADV2_THINK_MODEL export to spawned sessions (no -z skip-if-pinned guard)
PASS: priors-compile: no opus baseline rec for think roles (architect/critic on fable)
PASS: zero opus-4 literals under plugins/leadv2/{scripts,config,ref,workflows,hooks}
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 584: /escape-cmd.sh: Operation not permitted
FAIL: architect-escape-mission.md: extracted bash block fails bash -n
PASS: architect-escape-mission.md: referenced router script exists (/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/leadv2-router.sh)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 601: /quota-live.sh: Operation not permitted
chmod: /quota-live.sh: No such file or directory
mkdir: /lockout-empty: Operation not permitted
PASS: pool orders fable before opus (codex:unknown:,glm:unknown:,kimi:author:,fable:unknown:,opus:unknown:,sonnet:unknown:)
FAIL: fable not ok in pool — anthropic bucket mapping missing: pool=codex:unknown:,glm:unknown:,kimi:author:,fable:unknown:,opus:unknown:,sonnet:unknown:
FAIL: reviewer expected fable, got: reviewer=sonnet
FAIL: author-exclusion broke: pool=codex:unknown:,glm:unknown:,kimi:excluded:safety,fable:unknown:,opus:author:,sonnet:unknown: / reviewer=sonnet
PASS: dispatch-code.sh: no hardcoded opus prepass default
PASS: dispatch-code.sh prepass default resolves via router think-model
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 727: /leadv2-diverge-think-block.js: Operation not permitted
cat: /leadv2-diverge-think-block.js: No such file or directory
FAIL: leadv2-diverge.js JS channel (unresolved 'fable' pin + killing yaml -> opus) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='opus' agent_calls=1)
cat: /leadv2-diverge-think-block.js: No such file or directory
FAIL: leadv2-diverge.js JS channel (yaml allows -> fable (router round-trip, not a hardcoded default)) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='fable' agent_calls=1)
cat: /leadv2-diverge-think-block.js: No such file or directory
FAIL: leadv2-diverge.js JS channel (explicit a.model override wins outright, agent() never called) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='sonnet' agent_calls=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 727: /leadv2-diagnose-think-block.js: Operation not permitted
cat: /leadv2-diagnose-think-block.js: No such file or directory
FAIL: leadv2-diagnose.js JS channel (unresolved 'fable' pin + killing yaml -> opus) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='opus' agent_calls=1)
cat: /leadv2-diagnose-think-block.js: No such file or directory
FAIL: leadv2-diagnose.js JS channel (yaml allows -> fable (router round-trip, not a hardcoded default)) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='fable' agent_calls=1)
cat: /leadv2-diagnose-think-block.js: No such file or directory
FAIL: leadv2-diagnose.js JS channel (explicit a.model override wins outright, agent() never called) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='sonnet' agent_calls=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 727: /leadv2-learn-think-block.js: Operation not permitted
cat: /leadv2-learn-think-block.js: No such file or directory
FAIL: leadv2-learn.js JS channel (unresolved 'fable' pin + killing yaml -> opus) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='opus' agent_calls=1)
cat: /leadv2-learn-think-block.js: No such file or directory
FAIL: leadv2-learn.js JS channel (yaml allows -> fable (router round-trip, not a hardcoded default)) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='fable' agent_calls=1)
cat: /leadv2-learn-think-block.js: No such file or directory
FAIL: leadv2-learn.js JS channel (explicit a.model override wins outright, agent() never called) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='sonnet' agent_calls=0)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 727: /leadv2-po-feedback-loop-think-block.js: Operation not permitted
cat: /leadv2-po-feedback-loop-think-block.js: No such file or directory
FAIL: leadv2-po-feedback-loop.js JS channel (unresolved 'fable' pin + killing yaml -> opus) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='opus' agent_calls=1)
cat: /leadv2-po-feedback-loop-think-block.js: No such file or directory
FAIL: leadv2-po-feedback-loop.js JS channel (yaml allows -> fable (router round-trip, not a hardcoded default)) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='fable' agent_calls=1)
cat: /leadv2-po-feedback-loop-think-block.js: No such file or directory
FAIL: leadv2-po-feedback-loop.js JS channel (explicit a.model override wins outright, agent() never called) DEAD: THINK_MODEL='<empty>' agent_calls='<empty>' (expected THINK_MODEL='sonnet' agent_calls=0)
mkdir: /noyaml: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 758: /noyaml/yaml.py: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fable-think-tier.sh: line 759: /cap-available.yaml: Operation not permitted
PASS: resolver fails CLOSED when PyYAML missing: fable available -> opus (via unavailable:true degradation)
PASS: resolver stays CLOSED when PyYAML missing + fable unavailable -> opus
PASS=39 FAIL=19
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-fable-think-tier.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-freepool-gets-work.sh (scope-selected ad-hoc)
PASS: bash syntax: dispatcher + arbiter
FAIL: green: Standard tests/docs-only lane resolves arm=freepool without --protected -- rc=0 [leadv2-dispatch-code] launchable_seam task=feb927ef source=registry kind=code
[leadv2-dispatch-code] ladder_fallback_appended task=feb927ef tail=glm,glm-flash
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=codex model=gpt-6-astra tier=volume effort=medium task=feb927ef reason=capability_fit arbiter_pick=codex util_glm=99 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=freepool:price_ratio,glm:capped,glm-flash:capped,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=1 complexity=standard duration_class=unknown complexity_policy=capability_fit remaining=80.0 reset_in=n/a reset_basis=unknown_window probe_outage=claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=codex fit_differs=1 fit_bucket=codex:0,codex:0,sonnet:0,freepool:1
[leadv2-dispatch-code] candidate_chain task=feb927ef arms=codex,sonnet,freepool,glm,glm-flash
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=codex task=feb927ef rule=none reason=capability_fit
route_resolved by=router router=arbiter model=codex task=feb927ef rule=none reason=capability_fit
[leadv2-dispatch-code] dispatch_rolled_back reason=no_spawn_dry_run task=feb927ef
[leadv2-dispatch-code] active_lane_release_skipped task=feb927ef id=dispatch-feb927ef where=exit_trap reason=not_owner_row_intact rows=1 removed=0 live_worker_kept=0
PASS: green: journal carries deciding test/docs write-set derivation
PASS: green: Standard tests/docs-only lane is below the preserved capability floor
PASS: RED: negative control A always-protected mutation blocks freepool for the tests/docs lane
PASS: RED: negative control C forced-floor mutation demotes freepool for the tests/docs lane
PASS: floor-applied route_resolved keeps reason=cheapest_capable (floor_reason no longer overwrites it)
PASS: green: classifier escalation journals requested class, resolved class, and reason
PASS: RED: negative control D suppressing override journal removes the required trace
FAIL: green: production dispatcher remains freepool-admitting after mutation controls -- rc=0
SUMMARY: pass=8 fail=2
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-freepool-gets-work.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-glm-flash-arm.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/lib/leadv2-route-arbiter.sh (incl. 3.2)
[TEST] PASS: py_compile scripts/lib/leadv2-glm-policy-resolve.py
[TEST] PASS: run path: GLM_MODEL=glm-5.3-flash exported as ANTHROPIC_DEFAULT_SONNET_MODEL
[TEST] PASS: run path: default model unchanged (glm-5.3) when GLM_MODEL unset
[TEST] PASS: bg path: meta.yaml records model: glm-5.3-flash (run 260908-145040-repo-622c)
[TEST] PASS: bg path: meta.yaml carries glm-5.3-flash; bounded child-env probe had no capture
[TEST] FAIL: arbiter: expected arm=glm-flash model=glm-5.3-flash — got: arm=glm kind=code model=glm-5.3 tier=standard effort=medium reason=capability_fit chain=glm,codex,sonnet,glm-flash util_glm=10 util_codex=20 util_claude=unknown_capped util_freepool=100 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:capped,glm-flash:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,glm-flash:1
[TEST] PASS: protected: glm-flash absent from arm and chain — arm=glm kind=code model=glm-5.3 tier=standard effort=high reason=cheapest_capable chain=glm,codex,sonnet util_glm=10 util_codex=20 util_claude=unknown_capped util_freepool=100 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:untrusted,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0
[TEST] FAIL: NC: mutant did NOT route protected work to glm-flash (control is vacuous) — arm=glm kind=code model=glm-5.3 tier=standard effort=high reason=capability_fit chain=glm,codex,sonnet,glm-flash util_glm=10 util_codex=20 util_claude=unknown_capped util_freepool=100 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:untrusted,glm-flash:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=299ed19555f4 floor_mode=bulk_only floor_mode_source=default test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,glm-flash:1
[TEST] PASS: NC(revert): live config unchanged (flash cell protected: false)
[TEST] PASS: vocab: glm-flash dispatchable-build, review-excluded, not a plan arm
[TEST] FAIL: dispatch: launcher spawned (glm arm) but GLM_MODEL unset — arbiter did not pick glm-flash? dispatch tail: [leadv2-dispatch-code] route_resolved by=router router=arbiter model=glm task=5527f21c rule=none reason=capability_fit
route_resolved by=router router=arbiter model=glm task=5527f21c rule=none reason=capability_fit
[leadv2-dispatch-code] model_select_telemetry task=5527f21c role=worker class=standard work_kind=build arm=glm model=glm-5.3 fallback_depth=0 floor=applied spawn_to_terminal_s=4 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=5527f21c founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/5527f21c
[leadv2-dispatch-code] lane worktree left on disk for task=5527f21c: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/5527f21c
[TEST] PASS: resolver: protected glm-flash is refused to sonnet even without tenant safety exception
[TEST] PASS: NC(red): removing final glm-flash refusal leaks protected work to glm-flash
/Users/kostiantyn.vlasenko/Projects/getmany-followup-bot/.claude/ref/leadv2-routing.yaml: missing glm-flash
[TEST] FAIL: tenant drift: explicit review_arm_exclusions omit a default GLM family arm (checked 2)
[TEST] PASS: NC(red): tenant [glm] exclusion list is rejected after glm-flash default is added
[TEST] FAIL: quota refusal: missing glm-flash attribution or both-arm drop (journal=append dispatch-0b5fed65 decision project_root_guard task=0b5fed65 status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.KysTzI/glm-flash-fixture.5x13AJ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
append dispatch-0b5fed65 decision lane_plan_missing task=0b5fed65 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/0b5fed65/context.yaml carried_siblings=0
append dispatch-0b5fed65 decision task_class=Standard route=phases source=derived task=0b5fed65
append dispatch-0b5fed65 decision complexity_gate_applied task=0b5fed65 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
append dispatch-0b5fed65 decision brain_decision task=0b5fed65 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,deploy,live_verify,close reason=no_explicit_class
append dispatch-0b5fed65 decision cost_estimate_recorded task=0b5fed65 founder_task=0b5fed65 complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/0b5fed65/cost-estimate.yaml
append dispatch-0b5fed65 decision dispatch_classified task=0b5fed65 class=product reason=conservative_default kind=code asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
phase_precondition_bootstrap task=0b5fed65 class=Standard would_be_missing=classify,plan,gate1
append dispatch-0b5fed65 decision phase_precondition_bootstrap task=0b5fed65 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
append dispatch-0b5fed65 decision lane_writes task=0b5fed65 source=row writes=src/x.py
append dispatch-0b5fed65 decision mission_writeset_gate_disabled task=0b5fed65 reason=REQUIRE_MISSION_WRITESET=0 note=no_write_scope_check_ran
append dispatch-0b5fed65 decision architect_prepass task=0b5fed65 status=disabled reason=kill_switch
append dispatch-0b5fed65 decision protection_derived by=router task=0b5fed65 writes=src/x.py write_class=standard writes_protected=0 manual_protected=0 effective_protected=0
append dispatch-0b5fed65 decision arm_resolved job=build arm=glm-flash reason=none complexity=standard duration_class=medium
append dispatch-0b5fed65 decision launchable_seam task=0b5fed65 source=registry kind=code
append dispatch-0b5fed65 decision arm_floor_applied arm=freepool task=0b5fed65 reason=standard/code
append dispatch-0b5fed65 decision freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=0b5fed65
append dispatch-0b5fed65 decision launchable_seam task=0b5fed65 source=registry kind=code
append dispatch-0b5fed65 decision launchable_seam task=0b5fed65 source=registry kind=code
append dispatch-0b5fed65 decision route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=medium task=0b5fed65 reason=capability_fit arbiter_pick=glm util_glm=10 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:price_ratio,glm-flash:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_applied=1 floor_reason=standard/code floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=standard duration_class=medium complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=claude failure_memory=unavailable complexity_source=flag conf=0.7 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,glm-flash:1,freepool:1
append dispatch-0b5fed65 decision candidate_chain task=0b5fed65 arms=glm,codex,sonnet,glm-flash,freepool
append dispatch-0b5fed65 decision worker_env_assert arm=glm task=0b5fed65 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
append dispatch-0b5fed65 decision worker_env_assert arm=glm task=0b5fed65 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
append dispatch-0b5fed65 decision code_intel_preamble arm=glm task=0b5fed65 mode=attached
append dispatch-0b5fed65 decision effort_applied by=router arm=glm task=0b5fed65 effort=high think=off think_source=class_map mechanism=flag source=class_map resolved=medium
append dispatch-0b5fed65 decision arm_refused by=router model=glm task=0b5fed65 reason=glm_refused_quota_gate
append dispatch-0b5fed65 decision quota_lockout_recorded provider=glm arm=glm reason=quota_gate class=provider_refusal minutes=30 strikes=1 source=default
append dispatch-0b5fed65 decision launchable_seam task=0b5fed65 source=registry kind=code
append dispatch-0b5fed65 decision route_headroom_chosen task=0b5fed65 arm=sonnet after=glm_quota_gate ordered=sonnet headroom={} credits={}} scores={} source=router_v2 unknown=none
append dispatch-0b5fed65 decision route_fallback from=glm to=sonnet task=0b5fed65 reason=glm_refused_quota_gate
append dispatch-0b5fed65 decision worker_env_assert arm=sonnet task=0b5fed65 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
append dispatch-0b5fed65 decision worker_env_assert arm=sonnet task=0b5fed65 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
append dispatch-0b5fed65 decision code_intel_preamble arm=sonnet task=0b5fed65 mode=attached
append dispatch-0b5fed65 decision launch_model_resolved task=0b5fed65 task_id=dispatch-0b5fed65 arm=sonnet resolved_model=sonnet
append dispatch-0b5fed65 decision spawn_failed by=router model=sonnet task=0b5fed65 rc=127 reason=launcher_nonzero_exit
append dispatch-0b5fed65 decision dispatch_rolled_back reason=all_arms_unavailable task=0b5fed65 attempts=glm_refused_quota_gate,sonnet_failed_launcher
append dispatch-0b5fed65 decision model_select_telemetry task=0b5fed65 role=worker class=standard work_kind=build arm=sonnet model=glm-5.3 fallback_depth=1 floor=applied spawn_to_terminal_s=7 terminal=fail cause=all_arms_unavailable
append dispatch-0b5fed65 decision dispatch_terminal task=0b5fed65 terminal=dead cause=all_arms_unavailable
append dispatch-0b5fed65 decision active_lane_release_skipped task=0b5fed65 id=dispatch-0b5fed65 where=exit_trap reason=not_owner_row_intact rows=1 removed=0 live_worker_kept=0; router=resolve --chain codex,sonnet,freepool --task-id 0b5fed65)
[TEST] FAIL: lock refusal: glm-flash journal attribution missing (journal=append dispatch-ac3e5945 decision project_root_guard task=ac3e5945 status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.KysTzI/glm-flash-fixture.5x13AJ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
append dispatch-ac3e5945 decision lane_plan_missing task=ac3e5945 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/ac3e5945/context.yaml carried_siblings=0
append dispatch-ac3e5945 decision task_class=Standard route=phases source=derived task=ac3e5945
append dispatch-ac3e5945 decision complexity_gate_applied task=ac3e5945 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
append dispatch-ac3e5945 decision brain_decision task=ac3e5945 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,deploy,live_verify,close reason=no_explicit_class
append dispatch-ac3e5945 decision cost_estimate_recorded task=ac3e5945 founder_task=ac3e5945 complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/ac3e5945/cost-estimate.yaml
append dispatch-ac3e5945 decision dispatch_classified task=ac3e5945 class=product reason=conservative_default kind=code asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
append dispatch-ac3e5945 decision dispatch_refused reason=writeset_overlap task=ac3e5945 blocked_by=dispatch-0b5fed65 paths=src/x.py writes=src/x.py
append dispatch-ac3e5945 decision dispatch_terminal task=ac3e5945 terminal=refused cause=writeset_overlap)
SUMMARY: pass=14 fail=6
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-glm-flash-arm.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/leadv2-ldaa.FVb4vF8cS3: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 30: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 34: /dispatch-lib.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 38: /fake-journal.sh: Operation not permitted
chmod: /fake-journal.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 42: /fake-phase-record.sh: Operation not permitted
chmod: /fake-phase-record.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 76: /repo/ledger.jsonl: No such file or directory
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 85: /repo/docs/handoff/dispatch-ldaa0001/mission.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 86: /repo/docs/handoff/dispatch-ldaa0001/lane-deliverable: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 59: /dispatch-lib.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 69: /adv.err: Operation not permitted
FAIL: T1: persisted declaration -- 8th arg='__NO_CLOSE__'
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 76: /repo/ledger.jsonl: No such file or directory
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 99: /repo/docs/handoff/dispatch-ldaa0002/mission.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 59: /dispatch-lib.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 69: /adv.err: Operation not permitted
FAIL: T2: mission fallback -- 8th arg='__NO_CLOSE__'
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 76: /repo/ledger.jsonl: No such file or directory
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 112: /repo/docs/handoff/dispatch-ldaa0003/mission.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 113: /repo/docs/handoff/dispatch-ldaa0003/lane-deliverable: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 59: /dispatch-lib.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 69: /adv.err: Operation not permitted
FAIL: T3: precedence -- 8th arg='__NO_CLOSE__'
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 76: /repo/ledger.jsonl: No such file or directory
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 126: /repo/docs/handoff/dispatch-ldaa0004/mission.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 127: /repo/docs/handoff/dispatch-ldaa0004/lane-deliverable: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 59: /dispatch-lib.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh: line 69: /adv.err: Operation not permitted
FAIL: T4a: unparsable decl -- 8th arg='__NO_CLOSE__'
FAIL: T4b: journal -- capture lacks ignored line: 
PASS=0 FAIL=5
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n syntax check
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.RQ8jAgWVJx: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-leadv2-dispatch-outcome-ledger.sh (scope-selected ad-hoc)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=7e9c859d status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=7e9c859d reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/7e9c859d/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=7e9c859d
[leadv2-dispatch-code] complexity_gate_applied task=7e9c859d complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=7e9c859d class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=7e9c859d founder_task=7e9c859d complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/7e9c859d/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=7e9c859d class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=7e9c859d class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=7e9c859d status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=7e9c859d status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7e9c859d status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=7e9c859d status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7e9c859d status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=7e9c859d founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=7e9c859d after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=7e9c859d id=dispatch-7e9c859d where=exit_trap rows=1 removed=1 live_worker_kept=0
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=30dda76e status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=30dda76e reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/30dda76e/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=30dda76e
[leadv2-dispatch-code] complexity_gate_applied task=30dda76e complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=30dda76e class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=30dda76e founder_task=30dda76e complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/30dda76e/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=30dda76e class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=30dda76e class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=30dda76e status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=30dda76e status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=30dda76e status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=30dda76e status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=30dda76e status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=30dda76e founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=30dda76e after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=30dda76e id=dispatch-30dda76e where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 1: setup — parallel lanes did not dispatch/die cleanly
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=257af541 status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=257af541 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/257af541/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=257af541
[leadv2-dispatch-code] complexity_gate_applied task=257af541 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=257af541 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=257af541 founder_task=257af541 complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/257af541/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=257af541 class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] phase_precondition_bootstrap task=257af541 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
[leadv2-dispatch-code] architect_prepass task=257af541 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=257af541 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=257af541 status=failed reason=no_lane_writes rejected_not_missing=0 remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=257af541 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=257af541 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=257af541 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=257af541 after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=257af541 id=dispatch-257af541 where=exit_trap rows=1 removed=1 live_worker_kept=0
[TEST] FAIL: 3: setup — first dispatch failed or fake process died too fast (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=c4c3307d status=foreign_env_overridden env_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.L0MX9t/dispatch-outcome-31216-1788868314.CGmD5Z/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d
[leadv2-dispatch-code] lane_plan_missing task=c4c3307d reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/docs/handoff/c4c3307d/context.yaml carried_siblings=0
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=c4c3307d
[leadv2-dispatch-code] complexity_gate_applied task=c4c3307d complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=c4c3307d class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_recorded task=c4c3307d founder_task=c4c3307d complexity=standard duration_class=medium phase=pre_arm_selection path=docs/handoff/c4c3307d/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=c4c3307d class=product reason=conservative_default kind=unknown asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
```

### Evidence: changed-scope core shard 2, partial raw output

```text

[CORE-OFFLINE] parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)
[TEST] FAIL: contract red-first (post=1)
[TEST] PASS: clean waiting result with unsatisfied deliverable classifies parked
[TEST] PASS: parked outcome carries continue next
[TEST] PASS: clean success stream replay is parked-shaped
[TEST] PASS: clean success with deliverable does not resume
[TEST] PASS: parked lane launches exactly one resume
[TEST] PASS: second parked exit does not loop
[TEST] PASS: second parked exit journals already_attempted
[TEST] FAIL: positive control died-with-work resume
[TEST] RESULT: pass=7 fail=2 skip=0
[CORE-OFFLINE] FAILED: parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)

[CORE-OFFLINE] quota stand-down duration (record-quota-lockout --hours)
[TEST] PASS: bash -n clean (leadv2-dispatch-code.sh)
[TEST] PASS: /bin/bash 3.2 -n clean (leadv2-dispatch-code.sh)
[TEST] PASS: Test 1: exit 0
[TEST] PASS: Test 1: locked_until_epoch ~= now+10800 (delta=0s)
[TEST] PASS: Test 1: source starts 'standdown:' (got standdown:provider_broken)
[TEST] PASS: Test 2: exit 0
[TEST] PASS: Test 2: expired lockout file overwritten, epoch now in the future
[TEST] PASS: Test 3: codex refused by the quota precheck (locked_until_epoch in the future)
[TEST] PASS: Test 4: exit 0
[TEST] PASS: Test 4: no lockout file written (legacy quota=no path)
[TEST] PASS: Test 4: journal shows arm_postspawn_verdict ... quota=no
[TEST] PASS: Test 5a: --hours abc -> rc0, no file, stderr names bad value
[TEST] PASS: Test 5b: --hours 0 -> rc0, no file
[TEST] PASS: Test 5c: --hours 999 (out of 1..168 range) -> rc0, no file
[TEST] PASS: Test 6: journal emits quota_standdown_recorded provider=codex hours=3
[TEST] PASS: Test 6: journal does NOT emit quota_lockout_recorded for a stand-down

[TEST] 16 passed, 0 failed

[CORE-OFFLINE] deferred-GLM ladder (V3-GLM-LADDER-01)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.tPdUUrUJ3P: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 58: /poison-kimi.sh: Operation not permitted
chmod: /poison-kimi.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 58: /poison-codex.sh: Operation not permitted
chmod: /poison-codex.sh: No such file or directory
mkdir: /root-ab: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-ab/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 93: /refusing-glm.sh: Operation not permitted
chmod: /refusing-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 104: /ab-rv2.sh: Operation not permitted
chmod: /ab-rv2.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 125: /ab-sonnet.sh: Operation not permitted
chmod: /ab-sonnet.sh: No such file or directory
FAIL: (a) park row missing for sig8=38131d44 -- deferred_file=<missing>
PASS: (a) poison fence held
FAIL: (b) glm-deferred --list missing sig8=38131d44 -- list_out=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-ab/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks
mkdir: /root-empty: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-empty/.claude/ref/leadv2-routing.yaml: No such file or directory
FAIL: (b) empty-state message wrong -- got='[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-empty/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks'
mkdir: /root-c: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-c/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 202: /journal-c.sh: Operation not permitted
chmod: /journal-c.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 204: /journal-c.log: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 93: /refusing-glm-c.sh: Operation not permitted
chmod: /refusing-glm-c.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 104: /c-rv2.sh: Operation not permitted
chmod: /c-rv2.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 125: /c-sonnet.sh: Operation not permitted
chmod: /c-sonnet.sh: No such file or directory
cat: /journal-c.log: No such file or directory
FAIL: (c) expected exactly 1 codex_credits_empty line after 2 runs, got 0 -- journal=
FAIL: (c) setup -- stamp file missing at /root-c/docs/leadv2/.codex-credits-empty.stamp
cat: /journal-c.log: No such file or directory
FAIL: (c) expected 2 codex_credits_empty lines after the back-dated 3rd run, got 0 -- journal=
mkdir: /stubs-d: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 271: /stubs-d/collector.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 288: /stubs-d/claude.sh: No such file or directory
chmod: /stubs-d/collector.sh: No such file or directory
chmod: /stubs-d/claude.sh: No such file or directory
FAIL: (d) founder-status-full.md not written -- renderer produced no artifact
mkdir: /root-neg: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-neg/.claude/ref/leadv2-routing.yaml: No such file or directory
FAIL: (d) unexpected sonnet-fallback line with zero fallbacks -- content=<missing>
mkdir: /root-e: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-e/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 93: /refusing-glm-e.sh: Operation not permitted
chmod: /refusing-glm-e.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 104: /e-rv2.sh: Operation not permitted
chmod: /e-rv2.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 125: /e-sonnet-6666.sh: Operation not permitted
chmod: /e-sonnet-6666.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 125: /e-sonnet-13089.sh: Operation not permitted
chmod: /e-sonnet-13089.sh: No such file or directory
FAIL: (e) expected count=2 after two distinct-sig8 refusals -- content=<missing>
FAIL: (e) park queue missing a row for one of the two sig8s -- content=<missing>
FAIL: (e) run 2's park row should carry reason=glm_refused_quota_precheck -- content=
mkdir: /root-e2: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 415: /bump-snippet.sh: Operation not permitted
FAIL: (e2) expected count=1 after two bumps of the same sig8 -- content=<missing>
mkdir: /root-retry: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-retry/.claude/ref/leadv2-routing.yaml: No such file or directory
mkdir: /root-retry: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 446: /r-rv2-glm.sh: Operation not permitted
chmod: /r-rv2-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 434: /root-retry/docs/leadv2/glm-deferred.jsonl: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 459: /ledger-g.sh: Operation not permitted
chmod: /ledger-g.sh: No such file or directory
FAIL: (g) expected 'reaped gggggggg fallback_landed' and the row gone from --list -- out=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks list=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 434: /root-retry/docs/leadv2/glm-deferred.jsonl: No such file or directory
FAIL: (h) expected 'skipped_no_mission hhhhhhhh' and the row still in --list -- out=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks list=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks
mkdir: /root-retry-i: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-retry-i/.claude/ref/leadv2-routing.yaml: No such file or directory
mkdir: /root-retry-i: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 494: /root-retry-i/docs/leadv2/glm-deferred.d/iiiiiiii.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 495: /root-retry-i/docs/leadv2/glm-deferred.jsonl: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 503: /ledger-i.sh: Operation not permitted
chmod: /ledger-i.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 93: /refusing-glm-i.sh: Operation not permitted
chmod: /refusing-glm-i.sh: No such file or directory
FAIL: (i) expected 'retry_failed iiiiiiii rc=...' and the row still in --list -- out=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry-i/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks list=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry-i/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks
mkdir: /root-retry-f: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 71: /root-retry-f/.claude/ref/leadv2-routing.yaml: No such file or directory
mkdir: /root-retry-f: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 527: /root-retry-f/docs/leadv2/glm-deferred.d/ffffffff.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 528: /root-retry-f/docs/leadv2/glm-deferred.jsonl: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 536: /ledger-f.sh: Operation not permitted
chmod: /ledger-f.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh: line 540: /glm-ok-f.sh: Operation not permitted
chmod: /glm-ok-f.sh: No such file or directory
FAIL: (f) retry-all did not spawn a new dispatch for the parked mission -- out=[leadv2-dispatch-code] ERROR: leadv2-state-path unresolved for glm-deferred.jsonl -- falling back to /root-retry-f/docs/leadv2/glm-deferred.jsonl
no deferred glm tasks
PASS: poison fence held across the suite

================================================
  glm-deferred-ladder suite: FAIL=1
================================================
[CORE-OFFLINE] FAILED: deferred-GLM ladder (V3-GLM-LADDER-01)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-arm-admission.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/lib/leadv2-route-arbiter.sh (incl. 3.2)
[TEST] PASS: case1 (ladder): protected + kind=code excludes cheap-arm/free-arm — got 'trusted-arm'
[TEST] PASS: case1 (arbiter): protected + kind=code picks trusted-arm — arm=trusted-arm kind=code model=t1 tier=standard effort=medium reason=cheapest_capable chain=trusted-arm util_glm=10 util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a ceiling_default=claude claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=cheap-arm:untrusted,free-arm:untrusted arb_rev=13cff1513f08 matrix_rev=d2f898f3f623 floor_mode=bulk_only floor_mode_source=default test_only=0 complexity=unknown duration_class=unknown complexity_policy=none remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=codex,claude failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=off fit_pick=trusted-arm fit_differs=0 fit_bucket=trusted-arm:0 cap_default=trusted-arm
[TEST] PASS: case2 (ladder): protected + kind=review admits free-arm — got 'trusted-arm cheap-arm free-arm'
[TEST] PASS: case2 (arbiter): protected + kind=review reaches free-arm — arm=free-arm kind=review model=f1 tier=standard effort=medium reason=cheapest_capable chain=free-arm,trusted-arm util_glm=10 util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a ceiling_default=freepool claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=trusted-arm:price_ratio arb_rev=13cff1513f08 matrix_rev=d2f898f3f623 floor_mode=bulk_only floor_mode_source=default test_only=0 complexity=unknown duration_class=unknown complexity_policy=none remaining=100.0 reset_in=n/a reset_basis=n/a probe_outage=codex,claude failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=off fit_pick=free-arm fit_differs=0 fit_bucket=free-arm:0,trusted-arm:0 cap_default=free-arm,trusted-arm
[TEST] PASS: case3: ladder and arbiter agree free-arm is admissible at light (ladder='trusted-arm cheap-arm free-arm' arbiter='arm=cheap-arm kind=code model=c1 tier=standard effort=medium reason=cheapest_capable chain=cheap-arm,free-arm,trusted-arm util_glm=10 util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a ceiling_default=glm claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=free-arm:price_ratio,trusted-arm:price_ratio arb_rev=13cff1513f08 matrix_rev=d2f898f3f623 floor_mode=bulk_only floor_mode_source=default test_only=0 complexity=unknown duration_class=unknown complexity_policy=none remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=codex,claude failure_memory=unavailable complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=off fit_pick=cheap-arm fit_differs=0 fit_bucket=cheap-arm:0,free-arm:0,trusted-arm:0 cap_default=cheap-arm,free-arm,trusted-arm')
[TEST] PASS: case4: mechanical build task resolves base-arm=cheap-arm (cheapest capable) — got 'cheap-arm'
[TEST] PASS: case4b: protected mechanical task still resolves base-arm=trusted-arm — got 'trusted-arm'
[TEST] PASS: case5: resolve_arm's own resolver invocation carries base-arm=cheap-arm — argv='--routing-yaml /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.k90uUr/arm-admission-fixture.A3KyOb/routing.yaml --job build --base-arm cheap-arm --signals {"mission_kind": "code", "protected_path": false, "safety_touched": false, "subsystem_count": 0.0, "needs_midflight_interaction": false, "ui_design_judgment": false, "glm_failure_count": 0.0, "glm_lock_busy": false}'
[TEST] PASS: NC(red) mutationA: reverting the writes_prod split re-excludes free-arm from review work — got 'trusted-arm'
[TEST] PASS: NC(red) mutationB: hardcoding the base-arm pick loses cheap-arm — got 'trusted-arm'
[TEST] PASS: NC(red) mutationC: dropping 'light' from free-arm's when: makes the ladder disagree with the arbiter again — ladder='trusted-arm cheap-arm'
[TEST] PASS: post-mutation GREEN: case2 still passes
[TEST] PASS: post-mutation GREEN: case3 (ladder) still passes
[TEST] PASS: post-mutation GREEN: case4 still passes
[TEST] PASS: post-mutation GREEN: case5 still passes
[TEST] PASS: repo hygiene: this suite left every repo path byte-identical (fixture-only mutation)

[SUMMARY] PASS=18 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh (scope-selected ad-hoc)
[TEST] PASS: A1 worker (env marker): silent exit, no beat, no session stamp
[TEST] PASS: A2 worker (worktree transcript path): silent exit, no beat
[TEST] PASS: A3 worker (mission-marker transcript content): silent exit, no beat
[TEST] PASS: A4 lead (pin): beat triggered + owner transcript stamped
[TEST] FAIL: A5 unknown: rc=0 journal=2026-09-08T11:38:08Z event=loop_armed_by_unknown_session loop=single-lead-beat-hook kind=unknown outcome=armed reason=no_transcript sid=none pid=51704 entrypoint=none
[TEST] FAIL: A6 root transcript: rc=0 journal tail=2026-09-08T11:38:08Z event=loop_armed_by_unknown_session loop=single-lead-beat-hook kind=unknown outcome=armed reason=no_worker_evidence sid=none pid=52338 entrypoint=none
[TEST] PASS: B1 owner pid died -> loop exited within one iteration
[TEST] FAIL: C1 stale transcript but loop still running (out: )
[TEST] FAIL: D0 live owner: loop died early (alive=NO beats=0)
[TEST] PASS: D0b unknown (no pin): loop FAILS CLOSED — not armed, journaled
[TEST] PASS: D1 lane-pulse-watch: dead owner -> watcher exited
[TEST] PASS: E1 LEADV2_WORKER_ARM=1 -> worker
[TEST] PASS: E2 LEADV2_SUBSESSION_ROLE=worker -> worker
[TEST] PASS: E3 LEADV2_SUBSESSION_ROLE=lead (not worker evidence) -> unknown
[TEST] PASS: E4 LEADV2_SESSION_KIND pin -> lead
[TEST] PASS: E5 worktree-cwd transcript path -> worker
[TEST] PASS: E6 mission marker in transcript head -> worker
[TEST] PASS: E9 marker beyond the 20-line window -> unknown (bounded read)
[TEST] PASS: E7 root project transcript, no signals -> unknown (FIXED: was lead)
[TEST] PASS: E8 no evidence -> unknown
[TEST] PASS: E10 reason=worktree_path on the path signal
[TEST] PASS: E10 reason=mission_transcript on the content signal
[TEST] PASS: E10 reason=no_worker_evidence for a clean root transcript
[TEST] PASS: E10 reason=no_transcript for an unreadable path
[TEST] PASS: F1 lib absent -> beat still runs + owner_check=unavailable journaled
[TEST] FAIL: F2 spawn grep gate: unpinned claude -p site(s) NOT on the known list:
plugins/leadv2/scripts/leadv2-active-registry.sh:370
plugins/leadv2/scripts/leadv2-active-registry.sh:2214
plugins/leadv2/scripts/leadv2-lane-liveness.sh:267
plugins/leadv2/scripts/leadv2-lane-liveness.sh:363

[TEST] PASS: NC1 mutation (predicate always lead): A1 invariant broke — control red as required
[TEST] FAIL: NC2 mutation NOT caught: loop still exited with check deleted
[TEST] PASS: NC3 mutation (worktree signal dropped): A2 invariant broke — control red as required
[TEST] PASS: NC4 mutation (pin stripped at task-judge): F2 gate red as required
[TEST] 24 passed, 6 failed
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.iVTK6uEm23: Operation not permitted
Traceback (most recent call last):
  File "<stdin>", line 5, in <module>
PermissionError: [Errno 1] Operation not permitted: '/classify.sh'
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh: line 40: /classify.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh: line 42: classify_product_work: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh: line 52: classify_product_work: command not found
FAIL: a: 
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh: line 42: classify_product_work: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh: line 60: classify_product_work: command not found
FAIL: b: 
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh: line 67: LEADV2_NON_PRODUCT_KINDS: unbound variable
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-classification-names-its-hatch.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh (scope-selected ad-hoc)
PASS: leadv2-dispatch-code.sh resolves lane guard in a no-lib consumer farm
PASS: leadv2-dispatch-ledger.sh resolves lane guard in a no-lib consumer farm
PASS: leadv2-dispatch-product-close.sh resolves lane guard in a no-lib consumer farm
PASS: lib/leadv2-admission-class.sh resolves lane guard in a no-lib consumer farm
PASS: missing local and canonical guards fail CLOSED (terminal=pass_unlanded)
PASS: canonical guard with a clean lane records terminal=landed
PASS: mutation control -- flipping the ledger fail-closed stub to fail-open lets a dirty lane record landed (RED without the guarantee)
PASS: restored ledger fail-closed stub returns the dirty lane to pass_unlanded (GREEN with the guarantee back)
PASS: all four consumer-farm loaders resolve via canonical fallback

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-checkpoint-commit-cutoff.sh (scope-selected ad-hoc)
[TEST] PASS: 1: checkpoint commit newer than created frees the row (sha=9ea552ee)
[TEST] PASS: 2: checkpoint commit older than created (stale attempt) stays blocked
[TEST] PASS: 3: phase8-passed.flag present stays blocked despite a fresh checkpoint commit
[TEST] PASS: 4: model-written CHECKPOINT.md note still frees the row (no commit sha attached)
[TEST] PASS: 5: missing lane worktree fails closed, no fallback to PROJECT_ROOT's own commit
[TEST] PASS: 6: lane keyed by founder task_id (14bd0c10/21f644a1 shape) resolves via task_id and frees the row
[TEST] PASS: 7: task_id AND sig8 both unresolvable stays blocked (fail-closed preserved)
[TEST] PASS: 8: empty task_id (no founder task) still resolves via sig8, no regression
----
PASS=8 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] PASS: bash -n test-dispatch-ledger-task-id.sh
[TEST] PASS: dispatch with --task-id exits 0
[TEST] PASS: pending dispatch ledger file exists
[TEST] PASS: ledger row's task_id equals the bound --task-id (N4-TESTRUNNER-FALSE-RED)
[TEST] PASS: ledger row's mission_path is empty for an inline (non-@file) mission, as expected
[TEST] PASS: C1: no --task-id -> reserve row task_id is EMPTY (identity absent, not the H1)
[TEST] PASS: C1: no --task-id, mission has H1 -> reserve row lane_label == H1 name-token (N7F-C1)
[TEST] PASS: C2: no --task-id, mission has no H1 -> reserve row task_id is empty (no invented name)
[TEST] PASS: C3: --task-id AND mission-H1 both present -> reserve row task_id == bound --task-id (rule 1 wins)
[TEST] PASS: C4: write-terminal with empty founder + display-name 7th arg -> task_id from display name, founder_task_id empty
[TEST] PASS: C5: write-terminal with 6 args (no display name) -> task_id falls back to founder (back-compat)
[TEST] PASS: F4: no --task-id, mission H1  -> renders OPS-42 (not the tasks.yaml title)
[TEST] PASS: F4b: --task-id OPS-42 -> renders the tasks.yaml title (identity lookup preserved)
[TEST] === 14 passed, 0 failed ===

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.PBiK93gIxm: Operation not permitted
mkdir: /.claude: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 76: cd: null directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 77: /.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 87: /fake-subsession.sh: Operation not permitted
chmod: /fake-subsession.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 112: cd: null directory
[TEST] FAIL: case1 setup: could not extract sig8 from dispatch output ()
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.BOtt8YkjZr: Operation not permitted
mkdir: /.claude: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 76: cd: null directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 77: /.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 87: /fake-subsession.sh: Operation not permitted
chmod: /fake-subsession.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh: line 187: cd: null directory
[TEST] FAIL: case2 setup: could not extract sig8 or no confirmed ledger row ()
[test-dispatch-retry-dead] pass=0 fail=2
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.nZrQGcGihA: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh: line 54: /detect.py: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh: line 139: /hazard.sh: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
[TEST] FAIL: hazardous shape was NOT flagged (detector blind to the live incident shape)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh: line 152: /safe-cd.sh: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
[TEST] PASS: cd-wrapped call is NOT flagged (matches every already-fixed suite in this repo)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh: line 165: /safe-stateroot.sh: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
[TEST] PASS: inline LEADV2_STATE_ROOT= is NOT flagged (fully sandboxed regardless of cwd)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh: line 178: /safe-export.sh: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
[TEST] PASS: earlier 'export LEADV2_STATE_BASE=' is NOT flagged (inherited by the call's env)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh: line 193: /no-root.sh: Operation not permitted
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
[TEST] PASS: no project-root override at all is NOT flagged (out of this detector's scope)
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
/opt/homebrew/Cellar/python@3.14/3.14.3_1/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python: can't open file '/detect.py': [Errno 2] No such file or directory
[TEST] PASS: real fleet (465 suites) has zero unguarded fixture-state-leak shapes

=== 5 passed, 1 failed ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-fixture-state-leak-guard.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: run path: GLM_EFFORT=low -> spawn argv carries --effort low
[TEST] PASS: run path: GLM_EFFORT unset -> no --effort flag (provider default max, pre-lane spawn shape)
[TEST] PASS: run path: GLM_EFFORT=ultramax rejected by whitelist -> flag omitted (fail-open)
[TEST] FAIL: bg path: bounded child-argv probe had no --effort capture (run 260908-144353-repo-20c1)
[TEST] PASS: dispatch: task-class Light -> launcher env GLM_EFFORT=low (end-to-end)
[TEST] PASS: dispatch: task-class Light journal proves class_map fired (source=class_map, effort=low)
[TEST] PASS: dispatch: task-class Standard -> launcher env GLM_EFFORT=high (end-to-end)
[TEST] PASS: dispatch: task-class Standard journal proves class_map fired (source=class_map, effort=high)
[TEST] PASS: dispatch: task-class Heavy -> launcher env GLM_EFFORT=max (end-to-end)
[TEST] PASS: dispatch: task-class Heavy journal proves class_map fired (source=class_map, effort=max)
[TEST] PASS: class map: trivial -> low (source=class_map)
[TEST] PASS: class map: light -> low (source=class_map)
[TEST] PASS: class map: bulk -> low (source=class_map)
[TEST] PASS: class map: standard -> high (source=class_map)
[TEST] PASS: class map: heavy -> max (source=class_map)
[TEST] PASS: class map: strategic -> max (source=class_map)
[TEST] PASS: class map: Light -> low (source=class_map)
[TEST] PASS: class map: Standard -> high (source=class_map)
[TEST] PASS: class map: Heavy -> max (source=class_map)
[TEST] PASS: class map: bogus-cls -> high (source=fallback)
[TEST] PASS: NC(map-body,red): deleting the class map body drives every class to source=fallback (detectable)
[TEST] PASS: NC(red): dropping the pass-through leaves the launcher env without GLM_EFFORT (part A red)
[TEST] PASS: NC(red): mutant journal reverted to effort_dropped (journal assertion red)
[TEST] PASS: routing yaml: parses; glm-flash cell cost corrected to 0.33
[TEST] FAIL: arbiter: light-size expected arm=glm-flash — got: arm=glm kind=code model=glm-5.3 tier=standard effort=medium reason=capability_fit chain=glm,codex,sonnet,glm-flash,freepool util_glm=10 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:price_ratio,glm-flash:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,glm-flash:1,freepool:1
[TEST] FAIL: arbiter: standard-size expected arm=glm-flash — got: arm=glm kind=code model=glm-5.3 tier=standard effort=medium reason=capability_fit chain=glm,codex,sonnet,glm-flash,freepool util_glm=10 util_codex=20 util_claude=unknown_capped util_freepool=0 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=no_usable_now claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,freepool:price_ratio,glm-flash:price_ratio,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_applied=1 floor_reason=standard/code floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=90.0 reset_in=5.00h reset_basis=default_full_period probe_outage=claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=1 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,glm-flash:1,freepool:1
[TEST] passed=25 failed=3
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-glm-flash-handle.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: dep floor: grep present and functional
[TEST] PASS: dep floor: git present and functional
[TEST] PASS: dep floor: python3 present and functional
[TEST] PASS: launcher: glm-5.3-flash bg prints a non-empty handle (260908-144622-repo-0e33)
[TEST] PASS: launcher: status <handle> true right after bg
[TEST] PASS: launcher: run record names model glm-5.3-flash
[TEST] PASS: fixture floor: fixture repo exists
[TEST] PASS: dispatcher: glm-family worker_spawned with handle 260908-144641-leadv2-013a
[TEST] PASS: dispatcher: no spawn_failed not_live/empty_handle rows
[TEST] PASS: dispatcher: status true on the journaled handle
[TEST] PASS: mutation_control_empty_bg_echo_yields_empty_handle (RED reproduced — confirms the suite's launcher case actually exercises the fix)
[TEST] test-glm-flash-handle: 13 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh (scope-selected ad-hoc)
[TEST] FAIL: W1 replay-safety: rc=0 pulse=
[TEST] FAIL: W2 beat: alive=no pulse=
[TEST] FAIL: W2 dedup noise: watcher exited at, or pulsed, the dedup row (H1)
grep: /tmp/leadv2-lane-pulse-watch-qegi5R/repo-cafe0213/docs/leadv2/tasks/dispatch-cafe0213/pulse.md: No such file or directory
[TEST] FAIL: W2 terminal: pulse=
[TEST] FAIL: W5 re-arm dedup: rc=0 event_lines=0
[TEST] FAIL: W3 pidfile: rc=0 before=0 after=0
[TEST] FAIL: W4a baseline: unpatched scratch copy wrote no pulse — the W4 flip below would be vacuous (H2)
[TEST] PASS: W4b negative control RED: tail -n 0 revert misses the pre-existing terminal (as it must)
[TEST] PASS: W6 negative control RED: review_gate-as-terminal revert dies before dispatch_terminal (as it must)
[TEST] FAIL: W7 watch_timeout: rc=0 pulse=
[TEST] FAIL: W8 derived timeout: default= glm= max= pinned= (expected 14700/20300/29100/777)
[TEST] FAIL: W9 worker death: rc=0 pulse=
[TEST] FAIL: W10: watcher never picked up the re-resolved journal — pulse=
[TEST] PASS: W10 PAIRED CONTROL RED: with re-resolve disabled, the stale journal never picks up the new phase (times out instead)
test-lane-pulse-watch: 3 passed, 11 failed
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-pulse-watch.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-writes-rejection-is-named.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.gcl3pcxZzf: Operation not permitted
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-writes-rejection-is-named.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh (scope-selected ad-hoc)
PASS: leadv2-event.sh: bash -n OK
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.KsVuaGUGum: Operation not permitted
FAIL: emit did not create /c1/myrepo.jsonl
FAIL: line 1 schema wrong: 
sed: /c1/myrepo.jsonl: No such file or directory
FAIL: expected seq=2 on line 2, got ''
PASS: missing --repo: fail-open (rc=0, no dir/file created)
mkdir: /c4: Operation not permitted
Traceback (most recent call last):
  File "<string>", line 2, in <module>
    with open('/c4/rotrepo.jsonl', 'wb') as f:
         ~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^
FileNotFoundError: [Errno 2] No such file or directory: '/c4/rotrepo.jsonl'
FAIL: rotation: expected rotrepo.jsonl.1 to exist after an over-threshold emit
mkdir: /harness: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh: line 122: /harness/harness.sh: No such file or directory
chmod: /harness/harness.sh: No such file or directory
FAIL: dispatch-code.sh call site 'worker_spawned' produced no event (dir=/site-worker_spawned)
FAIL: dispatch-code.sh call site 'arm_refused' produced no event (dir=/site-arm_refused)
FAIL: dispatch-code.sh call site 'worker_terminal' produced no event (dir=/site-worker_terminal)
FAIL: dispatch-code.sh call site 'question_asked' produced no event (dir=/site-question_asked)

================================================
  leadv2-event emitter: PASS=2 FAIL=8
================================================
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-model-select-telemetry.sh (scope-selected ad-hoc)
PASS: bash syntax: dispatch
FAIL: (a) win: telemetry line missing/unparseable (line: ''; log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/win-out.log) -- 
FAIL: (a) win: wrong terminal/cause () -- 
FAIL: (a) win: probe did not dispatch via freepool (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/win-out.log) -- 
FAIL: (a) fail: telemetry line missing/unparseable (line: ''; log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/fail-out.log) -- 
FAIL: (a) fail: wrong terminal/cause () -- 
FAIL: (a) fail: arm field wrong () -- 
FAIL: (b) CSV file missing (win: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/repo1/docs/leadv2/model-select-telemetry.csv, fail: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/repo2/docs/leadv2/model-select-telemetry.csv) -- 
FAIL: (b) CSV header count != 1 (; file: ) -- 
FAIL: (b) fail CSV row wrong () -- 
FAIL: (b) win CSV row wrong () -- 
PASS: (negative-control) telemetry call removed from a throwaway dispatch copy
PASS: (negative-control) copy lives in a $TMP mirror with symlinked siblings (H3)
PASS: (negative-control) with emission removed, (a)+(b) run RED: no journal line, no CSV
FAIL: (negative-control) mutation broke the dispatch itself, control is invalid (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/neg-out.log) -- 
FAIL: (e) H1 fallback: expected exactly 1 telemetry row, got 0 -- 
FAIL: (e) H1 fallback: row unparseable (line: '') -- 
FAIL: (e) H1 fallback: row lacks 'terminal=win cause=worker_spawned' (line: '') -- 
FAIL: (e) H1: row does not name the final arm/model (line: ''; log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/fb-out.log) -- 
PASS: (e) H1: refused arm's model absent from the row
FAIL: (e) H1: no route_fallback in probe — probe is void (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/fb-out.log) -- 
FAIL: (e) H1: CSV row wrong () -- 
PASS: (negative-control H1) per-candidate re-stamp mutated back to round-1 shape
FAIL: (negative-control H1) mutation did not reproduce the lie — (e) may be tautological (line: ''; log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/negh1-out.log) -- 
FAIL: (negative-control H1) mutated copy lost the fallback — control invalid (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/negh1-out.log) -- 
FAIL: (g1) v2 empty chain: expected exactly 1 telemetry row, got 0 -- 
FAIL: (g1) v2 empty chain: row unparseable (line: '') -- 
FAIL: (g1) v2 empty chain: row lacks 'terminal=fail cause=all_arms_exhausted' (line: '') -- 
FAIL: (g1) probe did not hit the expected terminal (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/g1-out.log) -- 
FAIL: (g2) v2 not-dispatchable: expected exactly 1 telemetry row, got 0 -- 
FAIL: (g2) v2 not-dispatchable: row unparseable (line: '') -- 
FAIL: (g2) v2 not-dispatchable: row lacks 'terminal=fail cause=all_arms_not_dispatchable_v2' (line: '') -- 
FAIL: (g2) retired-arm drop missing (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/g2-out.log) -- 
FAIL: (g3) quota-locked: expected exactly 1 telemetry row, got 0 -- 
FAIL: (g3) quota-locked: row unparseable (line: '') -- 
FAIL: (g3) quota-locked: row lacks 'terminal=fail cause=all_arms_quota_locked' (line: '') -- 
FAIL: (g3) precheck skip line missing (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/g3-out.log) -- 
FAIL: (g4) excluded: expected exactly 1 telemetry row, got 0 -- 
FAIL: (g4) excluded: row unparseable (line: '') -- 
FAIL: (g4) excluded: row lacks 'terminal=fail cause=all_arms_excluded' (line: '') -- 
FAIL: (g4) arm_excluded line missing (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/g4-out.log) -- 
FAIL: (g5) arbiter all-capped: expected exactly 1 telemetry row, got 0 -- 
FAIL: (g5) arbiter all-capped: row unparseable (line: '') -- 
FAIL: (g5) arbiter all-capped: row lacks 'terminal=fail cause=all_arms_capped' (line: '') -- 
FAIL: (g5) arbiter refusal line missing (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/g5-out.log) -- 
FAIL: (g6) quota-filter exhaustion: expected exactly 1 telemetry row, got 0 -- 
FAIL: (g6) quota-filter exhaustion: row unparseable (line: '') -- 
FAIL: (g6) quota-filter exhaustion: row lacks 'terminal=fail cause=all_arms_exhausted_quota' (line: '') -- 
FAIL: (g6) expected terminal not reached (log: /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.GnPsJc/fp06-telem.O3PC2Y/g6-out.log) -- 
FAIL: (h) M2: journal row not sanitized (line: '') -- 
FAIL: (h) M2: CSV column count wrong (missing; row: ) -- 
FAIL: (h) M2: comma value split the CSV row (missing; row: ) -- 
PASS: (h) M2: formula-leading CSV cell is neutralized
FAIL: (i) H4: rotation wrong (6001 lines) -- 
PASS: (i) H4: header survived rotation
FAIL: (i) H4: newest row lost (oldrow6000) -- 

=== 8 passed, 48 failed ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-model-select-telemetry.sh (scope-selected ad-hoc)
[CORE-OFFLINE] HERMETIC-VIOLATION (WARN, follow-up): plugins/leadv2/scripts/tests/test-model-select-telemetry.sh (scope-selected ad-hoc) dirtied docs/leadv2:
?? docs/leadv2/.lane-liveness-share/

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.Vl4Bkm5TdS: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 45: /journal.sh: Operation not permitted
chmod: /journal.sh: No such file or directory
test: 1 bootstrap lane with zero phase records is admitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 74: /journal.log: Operation not permitted
  FAIL: bootstrap admission should journal phase_precondition_bootstrap
test: 2 same lane, later dispatch, missing mandatory phase is refused
mkdir: /docs: Operation not permitted
test: 3 lead-authored brief admits plan, proof=attested
mkdir: /docs: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 115: /docs/handoff/TASK-BRIEF-01/brief.md: No such file or directory
mkdir: /docs: Operation not permitted
  FAIL: plan recorded from a brief should carry proof: attested (file: )
  FAIL: brief-satisfied plan should drop out of missing=, only gate1 left (rc=3, out=missing=plan,gate1
required=classify,plan,gate1,build,test,review,live_verify,close
unmet=plan,gate1,build,test,review,live_verify,close)
test: 3b non-brief-named artifact does NOT satisfy plan
mkdir: /docs: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 141: /docs/handoff/TASK-BRIEF-01/notes.md: No such file or directory
mkdir: /docs: Operation not permitted
  FAIL: non-brief-named artifact should record proof: unverified (file: )
test: 3c substantial non-brief-named plan note satisfies plan, proof=attested
mkdir: /docs: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 166: /docs/handoff/TASK-CR-01/continue-round-2.md: No such file or directory
mkdir: /docs: Operation not permitted
  FAIL: substantial continue-round-2.md should carry proof: attested (file: )
  FAIL: substance-satisfied plan should drop out of missing=, only gate1 left (rc=3, out=missing=plan,gate1
required=classify,plan,gate1,build,test,review,live_verify,close
unmet=plan,gate1,build,test,review,live_verify,close)
test: 3d placeholder content under a non-brief name does NOT satisfy plan
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 190: /docs/handoff/TASK-CR-01/continue-round-3.md: No such file or directory
mkdir: /docs: Operation not permitted
  FAIL: placeholder continue-round-3.md should record proof: unverified (file: )
test: 4 the printed remedy actually clears the refusal
mkdir: /docs: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 213: /docs/handoff/TASK-REMEDY-01/brief.md: No such file or directory
mkdir: /docs: Operation not permitted
  FAIL: assert after running the printed remedies should admit (rc=3, out=missing=plan
required=classify,plan,gate1,build,test,review,live_verify,close
unmet=plan,build,test,review,live_verify,close)
  FAIL: gate1 recorded via --reason should carry proof: attested (file: )
test: 4b gate1 done with no artifact and no reason is still refused by record
test: 5 Standard lane that genuinely skipped planning is still refused
mkdir: /docs: Operation not permitted
test: 6 is-bootstrap probe flips after the first record
mkdir: /docs: Operation not permitted
mkdir: /repo7: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 315: /stub-codex.sh: Operation not permitted
chmod: /stub-codex.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 315: /stub-glm.sh: Operation not permitted
chmod: /stub-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 315: /stub-sonnet.sh: Operation not permitted
chmod: /stub-sonnet.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 315: /stub-freepool.sh: Operation not permitted
chmod: /stub-freepool.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 330: /live.sh: Operation not permitted
chmod: /live.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 332: /free.sh: Operation not permitted
chmod: /free.sh: No such file or directory
test: 7 fresh Standard dispatch through dispatch-code.sh is admitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 359: /d7.out: Operation not permitted
  FAIL: fresh Standard dispatch should exit 0 (rc=1, out=)
  FAIL: admitted dispatch spawned no worker
  FAIL: fresh dispatch should journal phase_precondition_bootstrap
test: 7b same lane after plan+gate1 remedies is admitted and spawns
mkdir: /repo7: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 393: /repo7/docs/handoff/PPB-36c9123f/brief.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 359: /d7b.out: Operation not permitted
  FAIL: dispatch after remedies should exit 0 (rc=1, out=)
  FAIL: admitted dispatch spawned no worker
test: 7c false verified-plan claim through dispatch-code.sh is refused
mkdir: /repo7: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 419: /repo7/docs/handoff/PPB-c27ae38c/notes.md: No such file or directory
mkdir: /repo7: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 427: /repo7/docs/handoff/dispatch-c27ae38c/phases.d/plan.yaml.forged: No such file or directory
grep: /repo7/docs/handoff/dispatch-c27ae38c/phases.d/plan.yaml: No such file or directory
  FAIL: fixture: proof forgery did not land
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 429: /spawned.txt: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 359: /d7f.out: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 432: /spawned.txt: No such file or directory
  FAIL: false verified-plan claim should exit 3 (rc=1, out=)
grep: /d7f.out: No such file or directory
  FAIL: false claim refusal should name plan and gate1 ()
test: 7d --at-bootstrap claim is ignored, the store wins
mkdir: /repo7: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 457: cd: /repo7: No such file or directory
  FAIL: classify-only lane with --at-bootstrap must refuse (rc=1, out=)
test: 8 fresh Heavy dispatch through dispatch-code.sh is admitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 359: /d8.out: Operation not permitted
  FAIL: fresh Heavy dispatch should exit 0 (rc=1, out=)
  FAIL: Heavy dispatch should journal class_escalated to=Heavy because=subsystems_touched ()
  FAIL: Heavy bootstrap journal should read class=Heavy with the full mandatory csv including diverge (got: <none>)
  FAIL: Heavy dispatch did not journal phase_precondition_bootstrap
test: 8b Heavy lane after diverge/plan/gate1 remedies is admitted and spawns
mkdir: /repo7: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 508: /repo7/docs/handoff/PPB-090486c5/brief.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 515: /spawned.txt: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 359: /d8b.out: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh: line 517: /spawned.txt: No such file or directory
  FAIL: Heavy dispatch after remedies should exit 0 (rc=1, out=)
  FAIL: admitted Heavy dispatch spawned no worker (before= after=)
test: 8c Heavy lane with classify-only records still refuses, naming diverge
mkdir: /docs: Operation not permitted

[PHASE-PRECONDITION-BOOTSTRAP] pass=15 fail=24
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-plugin-papercuts.sh (scope-selected ad-hoc)

test: P1 loop beats through reader errors, stops only on real zeros
[TEST] FAIL: P1a setup: loop pid 17900 died immediately — the loop never ran (vacuous)
[TEST] FAIL: P1b setup: loop pid 18342 died immediately — the loop never ran (vacuous)

test: P2 pidfile cleanup must not delete a NEWER loop claim / suite leaves nothing
[TEST] FAIL: P2a setup: loop A never armed (no live pid in /tmp/leadv2-plugin-papercuts-QnnYBh/p2a.loop.pid)
[TEST] PASS: P2b: suite-scope run exited leaving no beat loop behind

test: P3 rejected codex tier fails LOUDLY at resolution, no fallthrough
[TEST] PASS: P3: tier=spark refused at resolution (rc=1, route_tier_invalid journaled, no route_resolved)
[TEST] PASS: P3b: tier=volume resolves and dispatches normally (rc=0)

test: P4 spawn fallthrough journals a failure naming the arm and reason
[TEST] PASS: P4: codex spawn failure journaled with arm + launcher reason, then route_fallback

test: P5 --resume-lane bare name resolves the lane worktree
[TEST] PASS: P5: bare lane name pins the lane worktree (rc=0)

test: P6 --resume-lane absolute path pins the same worktree
[TEST] PASS: P6: absolute path form pins the lane worktree (rc=0)
[TEST] PASS: P6b: unknown ref refuses with rc=5 and a message showing the accepted shapes

test: P7 task-add.sh dead-write refusal (fixture copy, stubbed curl)
[TEST] FAIL: P7 setup: consuming repo script not found at /Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.mAbk8L/home/Projects/persona-engine/scripts/task-add.sh — cannot run the fixture

test: P8 watcher argv carries --owner=<repo>:<lane>
[TEST] PASS: P8: spawned watcher argv carries the owner stamp (--owner=p8-repo:worktree-P8-LANE])
[TEST] PASS: P8b: explicit LEADV2_BEAT_OWNER_TAG overrides derivation

test-plugin-papercuts: 9 passed, 4 failed
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-plugin-papercuts.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-red-proof-gate.sh (scope-selected ad-hoc)
PASS: named_fixes: Critical heading extracted
PASS: named_fixes: High heading extracted
PASS: has_red: backed Critical fix satisfied
PASS: has_red: unbacked High fix correctly unproven
PASS: unproven: exactly one unproven line
PASS: unproven: names the correct fix
PASS: unproven: backed fix not flagged
PASS: C2: separate worker claim root is checked against founder RED evidence
PASS: C2: dispatch-titled completed worker report contributes its task claim
PASS: has_red: a '0 failed' artifact correctly does not satisfy its fix
PASS: has_red: backing artifact under round2-red/ (not just red/) satisfies the fix
PASS: named_fixes: a lane-mission.md heading is not read as a worker claim
PASS: named_fixes: a file without the completion marker is not read as a worker claim
PASS: CLI: close-gate reports unproven finding (never blocks -- rc=0)
PASS: control C1: mutated lib accepts '0 failed' as backing -> caught (would be red)
PASS: L1: leading-/ task_id rejected
PASS: L1: .. task_id rejected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-red-proof-gate.sh: line 241: _t11_default: unbound variable
FAIL: C3: production terminal-render anchor drifted (expected 5 call sites, rc=64)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-red-proof-gate.sh: line 241: _t11_default: unbound variable
FAIL: C3 control: nulled suffix still produced 0 downgrade mention(s), rc=64 -- C3 is not actually sensitive to the suffix
SUMMARY: pass=17 fail=2
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-red-proof-gate.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-single-lead-beat-loop.sh (scope-selected ad-hoc)
[TEST] PASS: B1 kill-switch: LEADV2_PULSE_MODE=0 / LEADV2_SINGLE_LEAD_BEAT=0 -> no-op, nothing armed
[TEST] FAIL: B2 beat driven: beats=0 loop_alive=no
[TEST] FAIL: B3 not armed twice: second invocation hung or stole the pidfile
[TEST] PASS: B4 stops on empty board: loop exited after consecutive zeros, pidfile removed
[TEST] FAIL: B4b re-arm after stop failed
[TEST] FAIL: B5 transient zero: loop died on a non-consecutive zero (H3)
[TEST] FAIL: B6 running_stale live: stale lane silenced the beat (H3)
[TEST] FAIL: B7 per-root pidfile: a=dead b=dead pidfiles=0
```

### Evidence: changed-scope core shard 3, partial raw output

```text

[CORE-OFFLINE] T13 slice2 (arbiter bench-fallback + abandon dedup)
[TEST] PASS: allowed_arms excludes glm/freepool from pick and chain
[TEST] FAIL: NEGATIVE CONTROL 1: mutated arbiter (no allowed_arms filter) unexpectedly still passed
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-t13-slice2.sh: line 163: _arm_launchable_arms: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-t13-slice2.sh: line 163: requested_arm: unbound variable
[TEST] PASS: bench-fallback re-arbitrates and emits route_headroom_chosen when primary arm benched
[TEST] PASS: NEGATIVE CONTROL 2: mutated dispatch (bench-fallback block removed) correctly fails case2
[TEST] PASS: exit76_receipt continuation re-arbitrates over remaining candidates and sets _reenter
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-t13-slice2.sh: line 211: _arb_fault_detail: command not found
[TEST] PASS: NEGATIVE CONTROL 2b: mutated dispatch (exit76 route_arbiter call broken) correctly fails case2b
[TEST] PASS: answered abandon decision deregisters the active.yaml row
[TEST] PASS: second reconcile does not re-ask the abandoned task
[TEST] PASS: NEGATIVE CONTROL 3: mutated lanes-snapshot (abandon consume removed) correctly fails case3
[TEST] PASS: NEGATIVE CONTROL 3b: mutated lanes-snapshot (abandon tombstone writer removed) correctly fails case3
[TEST] PASS: CLI dispatch table has no bypass subcommand beyond the documented phased-path set
[TEST] PASS: NEGATIVE CONTROL 4a: mutated dispatch (bogus bypass subcommand injected) correctly fails the CLI-surface scan
[TEST] PASS: every spawn_worker call site is preceded by a build-phase record AND a route_arbiter worker call
UNGATED_SPAWN line=9626
[TEST] PASS: NEGATIVE CONTROL 4b: mutated dispatch (cmd_advance_arm precondition guard stripped) correctly fails the spawn-gating scan
UNGATED_SPAWN line=9627
[TEST] PASS: NEGATIVE CONTROL 4c: mutated dispatch (F1 reverted: advance-arm arbiter call broken) correctly fails the spawn-gating scan

[SUMMARY] PASS=14 FAIL=1
[CORE-OFFLINE] FAILED: T13 slice2 (arbiter bench-fallback + abandon dedup)

[CORE-OFFLINE] dispatch arm vocabulary (kimi retirement)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.DB0ZVibx1X: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 65: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 73: /worker.sh: Operation not permitted
chmod: /worker.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 80: /poison-glm.sh: Operation not permitted
chmod: /poison-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 80: /poison-kimi.sh: Operation not permitted
chmod: /poison-kimi.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 80: /poison-codex.sh: Operation not permitted
chmod: /poison-codex.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 94: /resolver-stub.py: Operation not permitted
chmod: /resolver-stub.py: No such file or directory
FAIL: case1: dispatch exited 1 (the original bug) — rc=1
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 155: /harness.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 168: /harness.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 169: /harness.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 170: /harness.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 171: /harness.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 172: /harness.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 173: /harness.sh: Operation not permitted
bash: /harness.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 338: /harness-heavy.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 346: /harness-heavy.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 347: /harness-heavy.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 348: /harness-heavy.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 349: /harness-heavy.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 350: /harness-heavy.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 351: /harness-heavy.sh: Operation not permitted
bash: /harness-heavy.sh: No such file or directory
FAIL: case8: heavy-classified chain still reaches freepool (expected: 'sonnet', got: '')
PASS: case9: --task-class Heavy flows into DC_TASK_CLASS and excludes freepool
PASS: case10: both fanout call sites forward --task-class to dispatch-code.sh
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 223: /routing-kimi-spill.yaml: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh: line 232: /quota-live-stub.sh: Operation not permitted
chmod: /quota-live-stub.sh: No such file or directory
PASS: case5: resolver spill with kimi in tenant yaml → arm=glm (not kimi)
PASS: case6: router_v2.arms has 7 entries, kimi absent (glm glm-flash freepool codex claude-haiku claude-sonnet claude-opus)

================================================
  arm-vocabulary suite: PASS=4 FAIL=2
================================================
[CORE-OFFLINE] FAILED: dispatch arm vocabulary (kimi retirement)

[CORE-OFFLINE] plugin reliability (process liveness + role fallback + prepass/reorder signals)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.bhOoEUqm4F: Operation not permitted

[D1] _pc_process_alive — pid-file liveness (behavioral)
mkdir: /glm-runs: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 92: /glm-runs/test-handle/meta.yaml: No such file or directory
  ok: live meta pid detected as alive
  ok: dead meta pid detected as dead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 110: /glm-runs/test-handle/pgid: No such file or directory
  FAIL: live child pid in pgid file not detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 122: /glm-runs/test-handle/.lockref: No such file or directory
mkdir: /glm-runs: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 125: /glm-runs/.lock-deadbeef/pid: No such file or directory
  FAIL: live supervisor pid in lock_dir/pid not detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 140: /glm-runs/test-handle/meta.yaml: No such file or directory
  ok: self pid (82303) excluded — no self-match
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 149: /glm-runs/test-handle/meta.yaml: No such file or directory
  ok: parent pid (28370) excluded
  ok: no live processes detected as dead

[D1] _pc_reap_worker — kills exact pids (behavioral)
mkdir: /reap-test: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 178: /reap-test/pgid: No such file or directory
  FAIL: victim process still alive after reap
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 192: /reap-test/pgid: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 193: /reap-test/meta.yaml: No such file or directory
  ok: reap did not kill self (82303) or parent (28370)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 207: /reap-test/.lockref: No such file or directory
mkdir: /.lock-cafe1234: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 210: /.lock-cafe1234/pid: No such file or directory
  FAIL: victim from lock_dir/pid still alive
  ok: reap with no live processes is a no-op (rc=0)

[D2] claude-subsession agents_worktree_fallback frontmatter strip
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 238: /critic.md: Operation not permitted
awk: can't open file /critic.md
 source line number 1
  FAIL: agents source: frontmatter not stripped properly
  ok: source accepts agents_worktree_fallback in frontmatter-strip branch
mkdir: /main-checkout: Operation not permitted
mkdir: /wt: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 267: /main-checkout/.claude/agents/critic.md: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 274: /wt/mission.md: No such file or directory
  FAIL: worktree fallback did not trigger (ROLE_SOURCE='')

[D3] prepass-park uses --no-block (fire-and-forget)
  ok: prepass-park uses --no-block, not blocking --timeout
  ok: prepass_parked journal line present

[D4] empty-status→dead grace guard (behavioral)
mkdir: /d4-test: Operation not permitted
  ok: source has meta-existence grace guard before empty-status dead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 364: /d4-test/meta.yaml: No such file or directory
sed: /d4-test/meta.yaml: No such file or directory
sed: /d4-test/meta.yaml: No such file or directory
  ok: old meta (>30s) + empty status → dead-eligible
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 392: /d4-test/meta.yaml: No such file or directory
  FAIL: fresh meta aged too fast (age=1788867367) — timing issue

[D5] router_v2 reorder failure journal
  ok: router_v2_reorder_failed journal line present

[PLUGIN-RELIABILITY-01] passed=13 failed=7
[CORE-OFFLINE] FAILED: plugin reliability (process liveness + role fallback + prepass/reorder signals)

[CORE-OFFLINE] codex instant-complete dead-arm spill (V3-ENV-GUARDS-01)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.NEOdb0ydth: Operation not permitted
[CORE-OFFLINE] FAILED: codex instant-complete dead-arm spill (V3-ENV-GUARDS-01)

[CORE-OFFLINE] prepass resume invalidation (LANE-OBSERVABILITY-02)
[TEST] PASS: R1a: first pinned run generated the prepass (sig8=6efde33a)
[TEST] PASS: R1b: .head sidecar stamped with the worktree HEAD
[TEST] PASS: R1c: artifact line 1 carries the base_head header
[TEST] FAIL: R2a: no status=cached in log:
[TEST] PASS: R2b: same-head resume did NOT invalidate
[TEST] FAIL: R3a: invalidation line wrong/missing: 
[TEST] FAIL: R3b: no archived architect-prepass.<epoch>.md
[TEST] FAIL: R3c: .head is '15fc73484754abdc1b2df4eb13da93d6e6147480' want '08e3a3d8fceb80bc41fe5a5d41d391a56c2cc177'
[TEST] FAIL: R3d: regenerated artifact line 1 is '<!-- leadv2-prepass base_head=15fc73484754abdc1b2df4eb13da93d6e6147480 generated_at=2026-09-08T11:36:51Z -->'
[TEST] FAIL: R3e: regeneration did not stabilise: 
[TEST] FAIL: R4: no prepass_refuted invalidation: 
[TEST] FAIL: R5: kill switch did not restore today: 

[prepass-resume-invalidate] PASS=4 FAIL=8
[CORE-OFFLINE] FAILED: prepass resume invalidation (LANE-OBSERVABILITY-02)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-arm-advance-real.sh (scope-selected ad-hoc)
FAIL: expected two worker_spawned lines, got 1
lane_plan_missing task=f3ea32c6 reason=source_absent source=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.yJORlE/armfix.c1h67Z/repo/docs/handoff/f3ea32c6/context.yaml carried_siblings=0
task_class=Standard route=phases source=classifier_error task=f3ea32c6
complexity_gate_applied task=f3ea32c6 complexity=standard complexity_source=flag pipeline_route=plan_first forced_plan=0 review_rounds=2
task_class_override by=admission task=f3ea32c6 requested=light resolved=Standard reason=classifier_error_fallback source=classifier_error
brain_decision task=f3ea32c6 class=Standard class_source=declared_fallback phases=classify,plan,gate1,build,test,review,live_verify,close reason=judge_unavailable
complexity_estimate_unavailable task=f3ea32c6 reason=judge_binary_missing degrade=arbiter_uses_size_only
complexity_floor_applied task=f3ea32c6 from=unknown to=standard source=flag by=flag
cost_estimate_recorded task=f3ea32c6 founder_task=f3ea32c6 complexity=standard duration_class=unknown phase=pre_arm_selection path=docs/handoff/f3ea32c6/cost-estimate.yaml
dispatch_classified task=f3ea32c6 class=product reason=conservative_default kind=code asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
phase_precondition_bootstrap task=f3ea32c6 class=Standard would_be_missing=classify,plan,gate1 mode=warn scope=pre-build
lane_writes task=f3ea32c6 source=row writes=src/proof.txt
mission_writeset_gate_disabled task=f3ea32c6 reason=REQUIRE_MISSION_WRITESET=0 note=no_write_scope_check_ran
architect_prepass task=f3ea32c6 status=disabled reason=kill_switch
protection_derived by=router task=f3ea32c6 writes=src/proof.txt write_class=standard writes_protected=0 manual_protected=0 effective_protected=0
arm_resolved job=build arm=glm-flash reason=none complexity=standard duration_class=unknown
arm_dropped_not_dispatchable arm=haiku task=f3ea32c6 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
arm_dropped_not_dispatchable arm=opus task=f3ea32c6 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
arm_dropped_not_dispatchable arm=fable task=f3ea32c6 router=v1 reason=not_in_DISPATCHABLE_BUILD_ARMS
launchable_seam task=f3ea32c6 source=registry kind=code
freepool_floor_mode mode=full source=default test_only=0 task=f3ea32c6
launchable_seam task=f3ea32c6 source=registry kind=code
launchable_seam task=f3ea32c6 source=registry kind=code
ladder_fallback_appended task=f3ea32c6 tail=glm,glm-flash,codex,sonnet
route_resolved by=arbiter role=worker arm=freepool model=freepool tier=standard effort=medium task=f3ea32c6 reason=forced arbiter_pick=freepool util_glm=90 util_codex=90 util_claude=90 util_freepool=0 floor_mode=full floor_mode_source=test
candidate_chain task=f3ea32c6 arms=freepool,glm,glm-flash,codex,sonnet
worker_env_assert arm=freepool task=f3ea32c6 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
worker_env_assert arm=freepool task=f3ea32c6 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
code_intel_preamble arm=freepool task=f3ea32c6 mode=skipped reason=fail_open cause=resolve_role_mcp_config_rc=12
effort_dropped by=router arm=freepool task=f3ea32c6 effort=medium reason=no_effort_control
worker_spawned by=router model=freepool task=f3ea32c6 attempt=f3ea32c6-1788867564-92211 handle=armfix-freepool
mission-version task=- sig=f3ea32c6 rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
product_close task=f3ea32c6 status=spawned author=freepool
route_resolved by=router router=arbiter model=freepool task=f3ea32c6 rule=none reason=forced
model_select_telemetry task=f3ea32c6 role=worker class=standard work_kind=code arm=freepool model=freepool fallback_depth=0 floor=none spawn_to_terminal_s=11 terminal=win cause=worker_spawned
lane_worktree_left task=f3ea32c6 founder_task= path=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/core-offline-run.geMTSw/suite.yJORlE/armfix.c1h67Z/repo/.claude/worktrees/f3ea32c6
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-arm-advance-real.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-board-blind-detached-workers-01.sh (scope-selected ad-hoc)
[TEST] Test 1: live detached glm worker (dead lead pid, handle only) -> verdict alive
[TEST] PASS: Test 1: detached glm worker live -> verdict=alive (was dead:no_log_artifact)
[TEST] Test 2: 2-poll snapshot prune keeps the live detached row; table renders it active
[TEST] PASS: Test 2: row still in active.yaml after 2 polls; table status=active
[TEST] Test 3: dead detached worker (group gone) -> verdict dead, row pruned — no leak
[TEST] PASS: Test 3: finished worker -> dead verdict, row pruned from active.yaml
[TEST] Test 4: exit-trap release path — disarmed-after-spawn row survives; worker-role row never released
[TEST] PASS: Test 4: disarmed trap keeps the detached row; worker-role row refused (not_owner_row_intact)
[TEST] Test 5: live detached codex job (handle only, job registry says running) -> verdict alive
[TEST] PASS: Test 5: detached codex job running -> verdict=alive

5 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-codex-refusal-cause.sh (scope-selected ad-hoc)
[TEST] PASS: T1 worker_died cooldown -> transport_cooldown marker, rc 2, never the quota word
[TEST] PASS: T2 queued_stall cooldown -> transport_cooldown marker
[TEST] PASS: T3 quota cooldown -> legacy quota_gate marker preserved (existing readers keep working)
[TEST] PASS: T4 circuit open -> quota_circuit_open marker
[TEST] PASS: T5 corrupt circuit marker -> circuit_unknown marker
[TEST] PASS: T6 non-executable provider gate -> gate_broken marker
[TEST] PASS: T7 live ceiling over threshold -> quota_gate marker (the real quota refusal is untouched)
[TEST] PASS: R1 refusal_reason extracts all five cause tokens
[TEST] PASS: C1 transport/circuit-unknown/gate_broken refusals write NO quota lockout and bump NO strike
[TEST] PASS: C2 quota cooldown -> lockout inherits the cooldown's reprobe_at exactly (strikes 0->1)
[TEST] PASS: C3 expiry-less quota refusal -> lockout row with the ~30min default expiry (negative control)
[TEST] PASS: C4 circuit open -> quota-family lockout inherits the circuit's until exactly
---
12 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.hnQsT3tylG: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh: line 27: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh: line 28: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh: line 30: /worker: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh: line 31: /architect: Operation not permitted
chmod: /worker: No such file or directory
chmod: /architect: No such file or directory
[leadv2-dispatch-code] lane_plan_skipped task=40f1bbd6 reason=shared_tree
[leadv2-dispatch-code] admission_receipt_write_failed task=40f1bbd6
[leadv2-dispatch-code] task_class=Standard route=phases source=derived task=40f1bbd6
[leadv2-dispatch-code] complexity_gate_applied task=40f1bbd6 complexity=standard complexity_source=heuristic pipeline_route=plan_first forced_plan=1 review_rounds=2
[leadv2-dispatch-code] brain_decision task=40f1bbd6 class=Standard class_source=computed phases=classify,plan,gate1,build,test,review,live_verify,close reason=no_explicit_class
[leadv2-dispatch-code] cost_estimate_unavailable task=40f1bbd6 reason=estimator_failed degrade=no_estimate_recorded phase=pre_arm_selection
[leadv2-dispatch-code] dispatch_classified task=40f1bbd6 class=product reason=conservative_default kind=product asserts=admission_strictness remedy=--kind:plugin|tooling|tool|docs|documentation|diagnosis|diagnostic|investigation
[leadv2-dispatch-code] active_register_miss task=40f1bbd6 rc=1
[leadv2-state-path] ABORT: parent of "/repo/docs/leadv2" is not writable -- refusing to proceed.
[leadv2-dispatch-code] lane_state_register_failed task=40f1bbd6 rc=1
[leadv2-dispatch-code] phase_precondition_bootstrap task=40f1bbd6 class=Standard would_be_missing=classify,plan,gate1 mode=1 scope=pre-build
mkdir: /repo: Operation not permitted
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=retrying attempt=1/2 reason=no_design
mkdir: /repo: Operation not permitted
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=retrying attempt=2/2 reason=no_design
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=40f1bbd6 founder_task_id= reason=no_design_after_2_attempts last_reason=unknown worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=40f1bbd6 after 2 attempts -- task PARKED, not dispatched.
find: /repo/docs/leadv2/tasks: No such file or directory
grep: : No such file or directory
FAIL missing parked-after-retries journal line
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.OBHs10BPUh: Operation not permitted
mkdir: /myrepo: Operation not permitted
mkdir: /myrepo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh: line 80: cd: /myrepo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh: line 81: /myrepo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh: line 66: /fake-subsession.sh: Operation not permitted
chmod: /fake-subsession.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh: line 92: cd: /myrepo/sub/deeper: No such file or directory
[TEST] FAIL: case1 setup: could not extract sig8 from dispatch output ()
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.ZfrV9nqizb: Operation not permitted
mkdir: /plainwork: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh: line 121: cd: /plainwork: No such file or directory
[TEST] FAIL: no-git + no-env: expected ledger slug=plainwork (pwd fallback), got: 
[test-dispatch-cwd-root-else-branch] pass=0 fail=2
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-outcome-terminal-retry.sh (scope-selected ad-hoc)
[leadv2-dispatch-code] dispatch_reclaimed task=11111111 arm=sonnet handle=65944 reason=terminal_refused
[TEST] PASS: 1: terminal=refused row frees a fresh dispatch (rc=1)
[leadv2-dispatch-code] dispatch_reclaimed task=22222222 arm=sonnet handle=65944 reason=terminal_dead
[TEST] PASS: 2: terminal=dead row frees a fresh dispatch (rc=1)
[TEST] PASS: 3: terminal=landed row still blocks (rc=0)
[TEST] PASS: 4: alive worker still blocks (rc=0) regardless of a refused terminal row
[TEST] PASS: 5: unknown liveness (empty handle) stays fail-closed (rc=0) despite a refused terminal row
[TEST] PASS: 6: dead+evidence with no terminal row stays blocked (rc=0, pre-existing protection intact)
----
PASS=6 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-usage-names-the-fault-last.sh (scope-selected ad-hoc)
mktemp: mkstemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.RS1lEYBRm0: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-usage-names-the-fault-last.sh: line 35: : No such file or directory
cat: : No such file or directory
FAIL: a: rc=1 last=''
FAIL: b: usage block missing from stderr
mktemp: mkstemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.EV4oUH6IQN: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-usage-names-the-fault-last.sh: line 35: : No such file or directory
cat: : No such file or directory
FAIL: c: rc=1 all=''
mktemp: mkstemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.2XfWiFQaeR: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-dispatch-usage-names-the-fault-last.sh: line 35: : No such file or directory
cat: : No such file or directory
FAIL: d: rc=1 all=''
[DISPATCH-USAGE-NAMES-THE-FAULT-LAST] pass=0 fail=4
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-dispatch-usage-names-the-fault-last.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.cM7LInVjYb: Operation not permitted
mkdir: /repo-a: Operation not permitted
mkdir: /repo-b: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 84: cd: /repo-a: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 85: cd: /repo-b: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 88: cd: /repo-a: No such file or directory
[TEST] FAIL: default (guard on): expected FOREIGN-PROJECT-ROOT-GUARD-01 warning (got: )
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 97: cd: /repo-a: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 98: cd: /repo-b: No such file or directory
[TEST] FAIL: default (guard on): expected warning to name repo A as cwd/winner (got: )
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.r06T8PyPgC: Operation not permitted
mkdir: /repo-a: Operation not permitted
mkdir: /repo-b: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 114: cd: /repo-a: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 115: cd: /repo-b: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 118: cd: /repo-a: No such file or directory
[TEST] PASS: explicit opt-out (flag=0): no warning, legacy env-wins precedence preserved
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.38dg7LegBQ: Operation not permitted
mkdir: /root: Operation not permitted
[TEST] PASS: bare-tmpdir override (no .git) passes through unchanged at the guard's default
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.slKbs1Bp0P: Operation not permitted
mkdir: /repo-a: Operation not permitted
mkdir: /repo-b: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 154: cd: /repo-a: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 155: cd: /repo-b: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 156: /repo-a/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 164: cd: /repo-a: No such file or directory
[TEST] FAIL: case4: could not extract sig8 from dispatch output ()
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.N5l6Kv3JUt: Operation not permitted
mkdir: /repo-a: Operation not permitted
mkdir: /real-env: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 189: cd: /repo-a: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 190: cd: /real-env: No such file or directory
ln: /link-env: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 193: cd: /real-env: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 199: cd: /repo-a: No such file or directory
[TEST] PASS: case5 (item 4): symlinked env root's genuine worktree pin is not falsely rejected
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.OqO3StHg0d: Operation not permitted
mkdir: /repo-a: Operation not permitted
mkdir: /real-env: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 217: cd: /repo-a: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 218: cd: /real-env: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 220: cd: /real-env: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh: line 226: cd: /repo-a: No such file or directory
[TEST] FAIL: case6 (item 4): parent env root + genuine pin was rejected (rc=1, out: )
[test-foreign-project-root-guard] pass=3 fail=4
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.X9TXiGofpk: Operation not permitted
Traceback (most recent call last):
  File "<stdin>", line 5, in <module>
PermissionError: [Errno 1] Operation not permitted: '/cap.sh'
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 47: /cap.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
FAIL: a: 2 -> passed
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
FAIL: b: 7 -> passed, 99 -> passed
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
PASS: values below the threshold still pass through unchanged
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh: line 49: _glm_failures_flag_is_ignored: command not found
PASS: a non-numeric or empty flag is not treated as a capped value
[GLM-FAILURES-FLAG-IS-CAPPED] pass=2 fail=2
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-glm-failures-flag-is-capped.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh (scope-selected ad-hoc)
[TEST] FAIL Q1-glm
[TEST] FAIL Q1-codex
[TEST] FAIL Q1-sonnet
[TEST] PASS Q2-basic
[TEST] PASS Q2-self
[TEST] FAIL Q3-pair
[TEST] PASS Q0-unset-safety
[TEST] PASS Q4-committed-lane
[TEST] PASS Q5-never-smaller-glm
[TEST] PASS Q5-never-smaller-sonnet
[TEST] FAIL Q6-bad-sha-fallback
[TEST] FAIL Q1-glm
[TEST] FAIL Q1-codex
[TEST] FAIL Q1-sonnet
[TEST] PASS Q2-basic
[TEST] PASS Q2-self
[TEST] FAIL Q3-pair
[TEST] PASS Q0-unset-safety
[TEST] PASS Q4-committed-lane
[TEST] PASS Q5-never-smaller-glm
[TEST] PASS Q5-never-smaller-sonnet
[TEST] FAIL Q6-bad-sha-fallback

Results (post-fix, live tree): 6 passed, 5 failed
FAIL: Q1-glm
FAIL: Q1-codex
FAIL: Q1-sonnet
FAIL: Q3-pair
FAIL: Q6-bad-sha-fallback
red-first: 0/6 post-fix-passing cases RED against pre-fix
GREEN-PRE-FIX (not evidence): Q2-basic
GREEN-PRE-FIX (not evidence): Q2-self
GREEN-PRE-FIX (not evidence): Q0-unset-safety
GREEN-PRE-FIX (not evidence): Q4-committed-lane
GREEN-PRE-FIX (not evidence): Q5-never-smaller-glm
GREEN-PRE-FIX (not evidence): Q5-never-smaller-sonnet
pre-fix-could-not-run: 0
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-registry-outlives-dispatcher.sh (scope-selected ad-hoc)
[TEST] PASS: dispatch exited 0 (glm spawn confirmed)
[TEST] PASS: lane-pulse watcher stub started and recorded its own pid
[TEST] PASS: registry row for dispatch-lrod0001 exists after dispatcher exit
[TEST] PASS: registry row remains registered after dispatcher exit
[TEST] PASS: production registry adopts the controlled watcher pid
[TEST] PASS: registry pid is the live watcher pid controlled by this test
[TEST] PASS: lane_alive(dispatch-lrod0001) becomes dead after the controlled watcher exits
[TEST] PASS: ephemeral own-repo registry roots consolidate without error
[TEST] PASS: durable own-repo registry contains the consolidated ephemeral lane
[TEST] PASS: board snapshot renders the consolidated ephemeral own-repo lane

[LANE-REGISTRY-OUTLIVES-DISPATCHER-01] passed=10 failed=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: bash -n leadv2-fanout-lane-launcher.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] FAIL: C1-glm -- post-fix rc=1, expected 0
[TEST] FAIL: C1-codex -- post-fix rc=1, expected 0
[TEST] FAIL: C1-sonnet -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: C2 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: C2-b -- post-fix rc=1, expected 0
[TEST] FAIL: C3 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: H4 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: H5 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: H6 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: M7 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: M8 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: L11 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: L12 -- passed against HEAD too (pre_rc=0)

Results: 4 passed(red->green), 8 failed, 5 green-pre-fix, 0 could-not-run
red=4 green-pre-fix=5 could-not-run=0
FAIL: C1-glm: post-fix did not pass (rc=1)
FAIL: C1-codex: post-fix did not pass (rc=1)
FAIL: C1-sonnet: post-fix did not pass (rc=1)
FAIL: C2-b: post-fix did not pass (rc=1)
FAIL: C3: post-fix did not pass (rc=1)
FAIL: H5: post-fix did not pass (rc=1)
FAIL: M7: post-fix did not pass (rc=1)
FAIL: L11: post-fix did not pass (rc=1)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh (scope-selected ad-hoc)
[CORE-OFFLINE] HERMETIC-VIOLATION (WARN, follow-up): plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh (scope-selected ad-hoc) dirtied docs/leadv2:
?? docs/leadv2/.lane-liveness-share/

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.ZH4uFEoHCF: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 36: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
[TEST] PASS: idle: resolver picks glm (primary)
[TEST] PASS: busy: resolver fires glm_lock_busy_no_second_channel -> sonnet
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.RGQwYQKvir: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 36: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 69: /glm-fake.sh: Operation not permitted
chmod: /glm-fake.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 78: /subsession.sh: Operation not permitted
chmod: /subsession.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 85: /journal.sh: Operation not permitted
chmod: /journal.sh: No such file or directory
[TEST] FAIL: expected route_resolved model=sonnet rule=glm_lock_busy_no_second_channel (rc=1, out: )
[TEST] PASS: re-resolve fires at most once (n=0)
[TEST] PASS: no blind-spill to kimi
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.INVlhEMOJC: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 36: /repo/.claude/ref/leadv2-routing.yaml: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 128: /glm-fake.sh: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 137: /glm-ok.sh: Operation not permitted
cp: /glm-ok.sh: No such file or directory
chmod: /glm-fake.sh: No such file or directory
chmod: /glm-ok.sh: No such file or directory
chmod: /subsession.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh: line 144: /journal.sh: Operation not permitted
chmod: /journal.sh: No such file or directory
[TEST] FAIL: expected arm_source=ladder_fallback on the terminal line (got: )
[TEST] FAIL: control: unmoved route must NOT carry arm_source= (got: )

=== 4 passed, 3 failed ===
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-phase-gate-default-class.sh (scope-selected ad-hoc)
  FAIL: T1: lowercase heavy should refuse (rc=0)
  FAIL: T1: refused line must carry canonical class=Heavy (log=phase_precondition_bootstrap_admit task=s1 class=Heavy missing=diverge,plan,gate1 mode=1 )
  FAIL: T2: garbage class should refuse as Standard (rc=0)
  FAIL: T2: refused line must carry class=Standard (log=phase_precondition_bootstrap_admit task=s2 class=Standard missing=plan,gate1 mode=1 )
  FAIL: T4: satisfied Standard should pass (rc=1)
  FAIL: T4: pass trace expected (log=phase_precondition_refused task=s4 class=Standard missing=plan required=classify,plan,gate1,build,test,review,live_verify,close unmet=plan,build,test,review,live_verify,close mode=1 )
  FAIL: T6: real journal missing dispatch_classified (journal=/tmp/leadv2-pgdc-PUGz0w/e2e/repo/docs/leadv2/tasks/dispatch-60d8faf0/journal.md)
  FAIL: T6: real journal (no stub) must carry phase_precondition_bootstrap with class+would_be_missing (journal=/tmp/leadv2-pgdc-PUGz0w/e2e/repo/docs/leadv2/tasks/dispatch-60d8faf0/journal.md)

[PHASE-GATE-DEFAULT-CLASS] pass=11 fail=8
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-phase-gate-default-class.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh (scope-selected ad-hoc)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh: line 67: /bin/ps: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh: line 67: /bin/ps: Operation not permitted
FATAL: worker argv unexpected: 
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-plugin-review-arms.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/leadv2-pra01.UpxxkcgyIm: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
mkdir: /repo: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 71: cd: /repo: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 76: /poison-glm.sh: Operation not permitted
chmod: /poison-glm.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 76: /poison-kimi.sh: Operation not permitted
chmod: /poison-kimi.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 76: /poison-codex.sh: Operation not permitted
chmod: /poison-codex.sh: No such file or directory
PASS: T1a: tenant routing yaml present at .claude/ref/leadv2-routing.yaml
PASS: T1b: tenant yaml parses under yaml.safe_load with non-empty protected_path_patterns
PASS: T1c: plugin script path -> protected
PASS: T1d: hooks/config/lib paths -> protected
PASS: T1e: docs markdown path -> NOT protected (deliberate)
PASS: T2a: --author glm keeps glm in pool tagged :author: (present but never selectable)
PASS: T2b: --author glm seats reviewer=sonnet (not the author)
PASS: T2c: --author opus tags opus:author: in pool
PASS: T2d: --author opus seats reviewer=sonnet (not the author)
PASS: T2e: kimi stays excluded:safety under protected-path signal (arm mix unchanged)
mkdir: /stale-tree: Operation not permitted
mkdir: /repo: Operation not permitted
cp: /stale-tree/scripts/leadv2-dispatch-code.sh: No such file or directory
cp: /stale-tree/scripts: Not a directory
cp: /repo/plugins/leadv2/scripts/leadv2-dispatch-code.sh: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 166: /fake-journal.sh: Operation not permitted
chmod: /fake-journal.sh: No such file or directory
FAIL: T3a: stale-tree exit -- expected rc=4, got 127
FAIL: T3b: refusal text -- stderr lacks the refuse line -- got: bash: /stale-tree/scripts/leadv2-dispatch-code.sh: No such file or directory
FAIL: T3c: remedy -- no remedy line
FAIL: T3d: journal line -- capture lacks dispatch_refused: 
PASS: T4a: escape hatch does not refuse (rc=127)
FAIL: T4b: downgrade warn -- no dispatch_stale_script_tree_warn line
PASS: T5(plugin-tree): passes provenance check (rc=1)
PASS: T8(plugin-tree): no 'value=127' (phase-record binary resolves from the plugin tree)
mkdir: /wt: Operation not permitted
cp: /wt/plugins/leadv2/scripts: No such file or directory
PASS: T5(worktree-style): passes provenance check (rc=127)
PASS: T8(worktree-style): no 'value=127' (phase-record binary resolves from the plugin tree)
mkdir: /handoff6: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 239: /d6.diff: Operation not permitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/1176c725614d/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh: line 241: /crash-resolver.py: Operation not permitted
chmod: /crash-resolver.py: No such file or directory
FAIL: T6a: engine unreviewed path -- rc=9, artifact=none
FAIL: T6b: status -- absent
FAIL: T6c: refusal -- absent
FAIL: T6d: resolver_rc -- not 1: 
FAIL: T6e: resolver_stderr -- 
FAIL: T6f: merge_blocked -- absent
FAIL: T6g: last line -- got: 
Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
FileNotFoundError: [Errno 2] No such file or directory: '/handoff6/review-gate.md'
FAIL: T7: field-set drift --  

plugin-review-arms: 15 pass, 13 fail
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-plugin-review-arms.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh (scope-selected ad-hoc)
[TEST] PASS: A1: dispatch exited 0
[TEST] PASS: A1: lane_placement_pinned to RESUME-ME-01
[TEST] PASS: A2: dispatch exited 0
[TEST] PASS: A2: lane_placement_pinned to RESUME-ME-01
[TEST] PASS: A2: foreign-root guard accepted the absolute-path pin
[TEST] PASS: round3: WARN text names the cwd-derived-root fallback
[TEST] PASS: round3: foreign-root telemetry assignments + fallback are live in source
[TEST] PASS: round3: absolute-branch check uses the linked-worktree porcelain helper
[TEST] PASS: A3[/nope/nothing-rlap]: dispatch exited 5
[TEST] PASS: A3[/nope/nothing-rlap]: refusal emitted
[TEST] PASS: A3[/nope/nothing-rlap]: refusal names the accepted shapes
[TEST] PASS: A3[/nope/nothing-rlap]: refusal echoes what was given
[TEST] PASS: A3[/tmp/leadv2-rlap-qC6myS/plain-dir]: dispatch exited 5
[TEST] PASS: A3[/tmp/leadv2-rlap-qC6myS/plain-dir]: refusal emitted
[TEST] PASS: A3[/tmp/leadv2-rlap-qC6myS/plain-dir]: refusal names the accepted shapes
[TEST] PASS: A3[/tmp/leadv2-rlap-qC6myS/plain-dir]: refusal echoes what was given
[TEST] PASS: A4: dispatch exited 5
[TEST] PASS: A4: refusal emitted
[TEST] PASS: A4: refusal names the accepted shapes
[TEST] PASS: A4: refusal echoes what was given
[TEST] PASS: A4: refusal has no doubled segment
[TEST] PASS: A5: dispatch exited 5
[TEST] PASS: A5: refusal emitted
[TEST] PASS: A5: refusal names the accepted shapes
[TEST] PASS: A5: refusal echoes what was given
[TEST] PASS: A6: dispatch exited 5
[TEST] PASS: A6: refusal emitted
[TEST] PASS: A6: refusal names the accepted shapes
[TEST] PASS: A6: refusal echoes what was given
[TEST] PASS: A7: dispatch exited 5
[TEST] PASS: A7: refusal emitted
[TEST] PASS: A7: refusal names the accepted shapes
[TEST] PASS: A7: refusal echoes what was given
[TEST] PASS: A9: dispatch exited 5
[TEST] PASS: A9: refusal emitted
[TEST] PASS: A9: refusal names the accepted shapes
[TEST] PASS: A9: refusal echoes what was given
[TEST] PASS: A8: dispatch exited 0
[TEST] PASS: A8: foreign-root WARN names the cwd-derived fallback
[TEST] PASS: A8: project_root_guard telemetry fired with both roots
test-resume-lane-arg-shapes: 40 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-single-writer-lane-state.sh (scope-selected ad-hoc)
PASS: T1: register -> build -> review -> finished -> mark_finished via the owner; exactly ONE row, terminal state correct
PASS: T2: one real body (registry) + one fail-loud helpers stub; fanout body relocated, aliased only in the registry
PASS: T3: genuinely unowned lane -> recovered_unowned row via lane_reconcile (recovery mechanism intact)
PASS: T4: update_phase rc=8 and mark_finished rc=8 on the recovery-owned row; row intact, refusal is loud
PASS: T5: live adoption cleared 'recovered'; update_phase succeeded again (rc=0, phase=review)
PASS: T6: recovered row past RETENTION (dead_at 2020) REMOVED by reconcile, reaped row named in stderr
PASS: T7: our dead row released rc=0; foreign LIVE row refused (rc!=0) and left intact
PASS: T8: sourcing leadv2-active-registry.sh leaves caller errexit OFF (the old silent-kill leak is fixed)
PASS: T9: reserve_lane registers pid-less row (p- session) then set_lane_pid stamps the worker pid

single-writer lane-state: PASS=9 FAIL=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-stream-attempt-isolation.sh (scope-selected ad-hoc)
[TEST] PASS: A2: launcher exits 0 on first attempt (rc=0)
[TEST] PASS: A2: exactly one attempt dir exists (got 1)
[TEST] PASS: A2: attempt stream is a regular file (not a symlink)
[TEST] PASS: A2: flat newest-pointer is a symlink
[TEST] PASS: A2: pointer resolves to attempt #1's real file
[TEST] PASS: A2: setup self-check — fake claude marker in stream
[TEST] PASS: A1: launcher attempt#1 exits 0 (rc=0)
[TEST] PASS: A1: launcher attempt#2 exits 0 (rc=0)
[TEST] PASS: A1: setup self-check — fake claude ran twice (2 attempt dirs, got 2)
[TEST] PASS: A1: attempt#1 real stream file exists
[TEST] PASS: A1: attempt#2 real stream file exists
[TEST] PASS: A1: two attempts' streams DIFFER (no truncation)
[TEST] PASS: A1: flat name is a symlink (pointer, not the file itself)
[TEST] PASS: A1: pointer resolves to attempt #2 (newest), not #1
[TEST] PASS: A1: setup self-check — fake marker in BOTH streams
[TEST] PASS: A3: attempt#1 pending-cost marker appears
[TEST] PASS: A3: TWO pending-cost markers coexist (attempt#1 not overwritten)
[TEST] PASS: A3: marker filenames are attempt-scoped (distinct)
[TEST] PASS: A3: marker#1 records its own attempts/<id> stream path
[TEST] PASS: A3: marker#2 records a DIFFERENT attempt's stream path
[TEST] PASS: B1: fallback sums ALL attempts exactly (spent: 160)
[TEST] PASS: B1: newest-pointer must not be double-counted (found 210)

[TEST] test-stream-attempt-isolation: 22 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh (scope-selected ad-hoc)
[TEST] PASS: 1: pending incumbent (no writes, inside window) refuses as writeset_pending naming blocked_by=WSR-INC-PEND, no paths=, age_s=/window_s present
[TEST] PASS: 2: real path overlap refuses as writeset_overlap naming blocked_by=WSR-INC-OVR with the colliding paths=
[TEST] PASS: 3: the two cases are distinguishable from the refusal text alone (reason + window_s= vs paths=)
[TEST] PASS: 4: negative control — with stderr re-swallowed (old 2>/dev/null), blocked_by disappears and the legacy writeset_conflict fallback fires
----
PASS=4 FAIL=0

[CORE-OFFLINE] plugins/leadv2/tests/test-exclusion-stages.sh (scope-selected ad-hoc)
mktemp: mkdtemp failed on /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.aU5Eutrk4T: Operation not permitted
ABORT: suite exited rc=1 WITHOUT a summary after 0 assertion(s); last completed: (none yet)
[CORE-OFFLINE] FAILED: plugins/leadv2/tests/test-exclusion-stages.sh (scope-selected ad-hoc)
```

## Closure

The code and registered regression are committed in the pinned lane. Both fault controls have red value assertions followed by a green restored suite. The official mutation artifacts are added in the final evidence commit, after this report is committed. No merge or push was performed. Delivery to live main remains with the lead.

BLOCKED: `tests/run-all.sh --scope changed` exited 124 at the 1,200-second bound with failures already present; integration verification remains unresolved.
