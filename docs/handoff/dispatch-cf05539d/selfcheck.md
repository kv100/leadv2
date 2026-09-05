# builder selfcheck — dispatch-cf05539d
generated_at: 2026-09-01T13:37:56Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01
diff_hash: 92ea14045d3b9a42da272ee8b4d1cd074743755dc61b49648c98bcb7639219d3
checks: 2   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] cost_estimate_recorded task=f71b71e6 founder_task=f71b71e6 arm=glm complexity=standard path=docs/handoff/f71b71e6/cost-estimate.yaml
[leadv2-dispatch-code] freepool_floor_mode mode=full source=yaml task=f71b71e6
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm-flash model=glm-5.3-flash tier=standard effort=low task=f71b71e6 reason=cheapest_capable arbiter_pick=glm-flash util_glm=62 util_codex=25 util_claude=62 util_freepool=100 floor_mode=full floor_mode_source=yaml complexity=standard duration_class=medium
[leadv2-dispatch-code] candidate_chain task=f71b71e6 arms=glm-flash,glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=f71b71e6 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=f71b71e6 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] effort_dropped by=router arm=glm-flash task=f71b71e6 effort=low reason=no_effort_control
[leadv2-dispatch-code] worker_spawned by=router model=glm-flash task=f71b71e6 attempt=f71b71e6-1788269744-97320 handle=fixture-38939
[leadv2-dispatch-code] mission-version task=- sig=f71b71e6 rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=glm-flash task=f71b71e6 attempt=f71b71e6-1788269744-97320 handle=fixture-38939
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=glm-flash task=f71b71e6 rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=glm-flash task=f71b71e6 rule=none reason=cheapest_capable
[leadv2-dispatch-code] model_select_telemetry task=f71b71e6 role=worker class=standard work_kind=build arm=glm-flash model=glm-5.3-flash fallback_depth=0 floor=none spawn_to_terminal_s=23 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=f71b71e6 founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01
[leadv2-dispatch-code] lane worktree left on disk for task=f71b71e6: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01)
  FAIL: refused dispatch spawned a fixture worker
  FAIL: refusal should identify plan and gate1 (out=[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/tmp/leadv2-phase-gate-EpKusA/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=f71b71e6 status=foreign_env_overridden env_root=/private/tmp/leadv2-phase-gate-EpKusA/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] lane_plan_missing task=f71b71e6 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/f71b71e6/context.yaml
[leadv2-dispatch-code] task_class=Standard route=phases source=flag task=f71b71e6
[leadv2-dispatch-code] dispatch_classified task=f71b71e6 class=non_product reason=explicit_kind_tooling kind=tooling
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=standard duration_class=medium
[leadv2-dispatch-code] cost_estimate_recorded task=f71b71e6 founder_task=f71b71e6 arm=glm complexity=standard path=docs/handoff/f71b71e6/cost-estimate.yaml
[leadv2-dispatch-code] freepool_floor_mode mode=full source=yaml task=f71b71e6
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm-flash model=glm-5.3-flash tier=standard effort=low task=f71b71e6 reason=cheapest_capable arbiter_pick=glm-flash util_glm=62 util_codex=25 util_claude=62 util_freepool=100 floor_mode=full floor_mode_source=yaml complexity=standard duration_class=medium
[leadv2-dispatch-code] candidate_chain task=f71b71e6 arms=glm-flash,glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=f71b71e6 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=f71b71e6 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] effort_dropped by=router arm=glm-flash task=f71b71e6 effort=low reason=no_effort_control
[leadv2-dispatch-code] worker_spawned by=router model=glm-flash task=f71b71e6 attempt=f71b71e6-1788269744-97320 handle=fixture-38939
[leadv2-dispatch-code] mission-version task=- sig=f71b71e6 rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=glm-flash task=f71b71e6 attempt=f71b71e6-1788269744-97320 handle=fixture-38939
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=glm-flash task=f71b71e6 rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=glm-flash task=f71b71e6 rule=none reason=cheapest_capable
[leadv2-dispatch-code] model_select_telemetry task=f71b71e6 role=worker class=standard work_kind=build arm=glm-flash model=glm-5.3-flash fallback_depth=0 floor=none spawn_to_terminal_s=23 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=f71b71e6 founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01
[leadv2-dispatch-code] lane worktree left on disk for task=f71b71e6: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01)
test: 2 approved new Standard dispatch is admitted
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01/plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh: line 93: task: unbound variable

verdict: RED
