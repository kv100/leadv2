# builder selfcheck — dispatch-bc72c541
generated_at: 2026-09-04T17:40:55Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01
diff_hash: 147d6bf8e9a001e5ce10d6cad7d5708a8b4ae46f107c297cc1dbf97b5b4ff78f
checks: 10   failed: 2   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 7 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-effort-routing.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-gets-work.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-routing-canonical-protected-glm.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-gets-work.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-route-arbiter.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-routing-canonical-protected-glm.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-effort-routing.sh (falsification proof) (rc=1)
PASS: adversarial-review kind resolves effort=high
PASS: mechanical/docs kind resolves effort=low
PASS: ordinary heavy code build resolves effort=medium
PASS: new yaml-only effort_matrix rule flips the outcome (no script edit)
PASS: unmodified routing.yaml still resolves medium (control for the anti-hardcode case)
PASS: standard build won by glm-flash (cheap/mechanical tags) resolves effort=medium
PASS: complex build resolves effort=high (task complexity, not arm tags)
FAIL: codex argv=<no argv captured> dispatch_out=[leadv2-dispatch-code] route_resolved by=router router=arbiter model=glm task=b7cc018f rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=glm task=b7cc018f rule=none reason=cheapest_capable
[leadv2-dispatch-code] model_select_telemetry task=b7cc018f role=worker class=light work_kind=diagnose arm=glm model=glm-5.3 fallback_depth=0 floor=none spawn_to_terminal_s=2 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=b7cc018f founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01
[leadv2-dispatch-code] lane worktree left on disk for task=b7cc018f: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01
FAIL: sonnet argv=<no argv captured> dispatch_out=[leadv2-dispatch-code] dispatch_classified task=9929fa65 class=product reason=conservative_default kind=code
[leadv2-dispatch-code] phase_precondition_refused task=9929fa65 class=Heavy missing=classify mode=1
[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: classify
[leadv2-dispatch-code] ERROR:   remedy: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01/plugins/leadv2/scripts/leadv2-phase-record.sh record 9929fa65 classify --artifact <path>
[leadv2-dispatch-code] active_lane_released task=9929fa65 id=dispatch-9929fa65 where=exit_trap rows=1 removed=1 live_worker_kept=0
FAIL: glm dispatch_out=[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm-flash model=glm-5.3-flash tier=standard effort=low task=66966be8 reason=cheapest_capable arbiter_pick=glm-flash util_glm=1 util_codex=1 util_claude=unknown_capped util_freepool=100 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=simple duration_class=short remaining=99.0 reset_in=5.00h reset_basis=default_full_period
[leadv2-dispatch-code] candidate_chain task=66966be8 arms=glm-flash,codex
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=66966be8 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=66966be8 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=glm-flash task=66966be8 mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm-flash task=66966be8 effort=low think=off think_source=class_map mechanism=flag source=class_map resolved=low
[leadv2-dispatch-code] worker_spawned by=router model=glm-flash task=66966be8 attempt=66966be8-1788543550-7129 handle=stub-1788543576-17473
[leadv2-dispatch-code] mission-version task=- sig=66966be8 rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=glm-flash task=66966be8 attempt=66966be8-1788543550-7129 handle=stub-1788543576-17473
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=glm-flash task=66966be8 rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=glm-flash task=66966be8 rule=none reason=cheapest_capable
[leadv2-dispatch-code] model_select_telemetry task=66966be8 role=worker class=light work_kind=diagnose arm=glm-flash model=glm-5.3-flash fallback_depth=0 floor=none spawn_to_terminal_s=2 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=66966be8 founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01
[leadv2-dispatch-code] lane worktree left on disk for task=66966be8: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SMART-ARBITER-01
RC=0
FAIL: decision line missing arm+effort: route_resolved by=router router=arbiter model=glm task=b7cc018f rule=none reason=cheapest_capable
SUMMARY: pass=7 fail=4

## raw — plugins/leadv2/scripts/tests/test-route-arbiter.sh (falsification proof) (rc=1)
PASS: codex 99% routes to a capable non-codex arm
PASS: all capped refuses all_arms_capped
PASS: protected chain excludes freepool and admits glm
PASS: anti-sticky identical tasks rotate arms
PASS: standard cell deterministically picks glm-flash (cost, not stickiness)
FAIL: fallback output=[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.QGXm057zIY/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=c4c38811 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.QGXm057zIY/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] lane_plan_missing task=c4c38811 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/c4c38811/context.yaml
[leadv2-dispatch-code] dispatch_classified task=c4c38811 class=product reason=conservative_default kind=code
[leadv2-dispatch-code] mission_writeset_gate_disabled task=c4c38811 reason=REQUIRE_MISSION_WRITESET=0 note=no_write_scope_check_ran
[leadv2-dispatch-code] architect_prepass task=c4c38811 status=disabled reason=kill_switch
[leadv2-dispatch-code] protection_derived by=router task=c4c38811 writes=src/x.py write_class=standard writes_protected=0 manual_protected=1 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=sonnet reason=none complexity=simple duration_class=short
[leadv2-dispatch-code] cost_estimate_recorded task=c4c38811 founder_task=c4c38811 arm=sonnet complexity=simple path=docs/handoff/c4c38811/cost-estimate.yaml
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=c4c38811 reason=protected_path
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=c4c38811
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=sonnet model=sonnet tier=standard effort=high task=c4c38811 reason=cheapest_capable arbiter_pick=sonnet util_glm=33 util_codex=92 util_claude=74 util_freepool=0 reset_glm=100.27h_live reset_codex=63.05h_live reset_claude=4.32h_live reset_freepool=n/a floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=simple duration_class=short remaining=26.0 reset_in=4.32h reset_basis=live
[leadv2-dispatch-code] candidate_chain task=c4c38811 arms=sonnet
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=sonnet task=c4c38811 rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=sonnet task=c4c38811 rule=none reason=cheapest_capable
[leadv2-dispatch-code] dispatch_rolled_back reason=no_spawn_dry_run task=c4c38811
[leadv2-dispatch-code] active_lane_release_skipped task=c4c38811 id=dispatch-c4c38811 where=exit_trap reason=not_owner_row_intact rows=1 removed=0 live_worker_kept=0
PASS: unknown --kind normalizes to code and resolves
PASS: fanout-class-funnel kind resolves an arm
PASS: backlog-pump kind resolves an arm
PASS: broken glm probe (status!=ok) is fail-closed, never selected
PASS: broken-active claude account falls back to the real ok account, not pct=0
SUMMARY: pass=10 fail=1

verdict: RED
