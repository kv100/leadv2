# builder selfcheck — dispatch-615b57f5
generated_at: 2026-08-23T21:11:29Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b
diff_hash: ff8e4d22939d6137e5ae4731c39ffebba229fbf1bbd555a00aeaaef97116c1a9
checks: 104   failed: 16   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 53 files > max 40 | FAIL (oversized_diff) |
| bash -n | plugins/leadv2/hooks/leadv2-compact-trigger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-instant-complete.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-checkpoint-commit-cutoff.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-outcome-terminal-retry.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-first-recovery.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-landed-at-spawn.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-placement-pin.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-dispatch-outcome-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-router-v2-toggle.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lockout-failure-class.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plan-run-contract.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-report-only-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-codex-base.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-st2-question-protocol.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-statusline-count-truth.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-stop-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-subsession-absolute-handoff-path.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-env-asserts.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/zzrepro-test-lpp.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-backlog-pump.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-codex-instant-complete.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-checkpoint-commit-cutoff.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-outcome-terminal-retry.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-glm-first-recovery.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-landed-at-spawn.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-lane-placement-pin.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-dispatch-outcome-ledger.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-router-v2-toggle.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lockout-failure-class.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plan-run-contract.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-report-only-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-review-codex-base.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-st2-question-protocol.sh | FAIL (test_failed:rc=3) |
| falsification | plugins/leadv2/scripts/tests/test-status-surface.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-statusline-count-truth.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-stop-gate.sh | 0 |
| falsification | plugins/leadv2/scripts/tests/test-subsession-absolute-handoff-path.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-env-asserts.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.u58nEpa7iK/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=40f1bbd6 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.u58nEpa7iK/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=40f1bbd6 class=product reason=conservative_default kind=product
[leadv2-dispatch-code] phase_precondition_warn task=40f1bbd6 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=failed reason=failed_rc_9 rc=9
[leadv2-dispatch-code] ERROR: architect prepass failed: 
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=retrying attempt=1/2 reason=failed_rc_9
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=failed reason=failed_rc_9 rc=9
[leadv2-dispatch-code] ERROR: architect prepass failed: 
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=retrying attempt=2/2 reason=failed_rc_9
[leadv2-dispatch-code] architect_prepass task=40f1bbd6 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=40f1bbd6 founder_task_id= reason=no_design_after_2_attempts last_reason=failed_rc_9
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=40f1bbd6 after 2 attempts -- task PARKED, not dispatched.
FAIL missing parked-after-retries journal line

## raw — plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh (falsification proof) (rc=1)
route_resolved by=router router=v1 model=sonnet task=9927da28 rule=none reason=resolver_error
[leadv2-dispatch-code] lane_worktree_left task=9927da28 founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b
[leadv2-dispatch-code] lane worktree left on disk for task=9927da28: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b)

[TEST] 1 passed, 1 failed
[TEST] Failures:
  - setup: no sig8 extracted from dispatch output, or ledger file never created (out_a=[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-race-17242-1787518263.t1ivcz/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=9927da28 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-race-17242-1787518263.t1ivcz/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=9927da28 class=non_product reason=explicit_mission_fast_path kind=unknown
s-20260823T205104Z-17273-17275
[registry] rendered /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//dispatch-race-17242-1787518263.t1ivcz/repo/docs/LEAD_V2_STATE.md (1 sessions, history_preserved=False)
[leadv2-dispatch-code] phase_precondition_warn task=9927da28 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none
[leadv2-dispatch-code] candidate_chain task=9927da28 arms=glm,codex,sonnet
[leadv2-dispatch-code] dispatch_refused reason=duplicate_task_signature task=9927da28 ledger=/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//dispatch-race-17242-1787518263.t1ivcz/cache/dispatch-ledger/leadv2.jsonl
dispatch_refused reason=duplicate_task_signature task=9927da28 out_b=[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-race-17242-1787518263.t1ivcz/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=9927da28 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-race-17242-1787518263.t1ivcz/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=9927da28 class=non_product reason=explicit_mission_fast_path kind=unknown
s-20260823T205104Z-17273-17275
[registry] rendered /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//dispatch-race-17242-1787518263.t1ivcz/repo/docs/LEAD_V2_STATE.md (1 sessions, history_preserved=False)
[leadv2-dispatch-code] phase_precondition_warn task=9927da28 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none
[leadv2-dispatch-code] candidate_chain task=9927da28 arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=9927da28 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=9927da28 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] arm_refused by=router model=glm task=9927da28 reason=glm_refused_quota_gate
[leadv2-dispatch-code] quota_lockout_recorded provider=glm arm=glm reason=quota_gate class=provider_refusal minutes=30 strikes=1 source=provider_time_clamped
[leadv2-dispatch-code] spawn(glm) refused: quota_gate
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-9927da28.stderr.log

[leadv2-dispatch-code] route_headroom_chosen task=9927da28 arm=sonnet after=glm_quota_gate ordered=sonnet headroom={"codex": 0.0, "sonnet": 0.3054124154941227} credits={"codex": {"balance": "0", "has_credits": false}}} scores={"codex":0.0,"sonnet":0.3054124154941227} source=router_v2 unknown=none
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=9927da28 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=9927da28 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=9927da28 attempt=9927da28-1787518264-17290 handle=PID=20396 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] mission-version task=- sig=9927da28 rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=sonnet task=9927da28 attempt=9927da28-1787518264-17290 handle=PID=20396 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] route_resolved by=router router=v1 model=sonnet task=9927da28 rule=none reason=resolver_error
route_resolved by=router router=v1 model=sonnet task=9927da28 rule=none reason=resolver_error
[leadv2-dispatch-code] lane_worktree_left task=9927da28 founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b
[leadv2-dispatch-code] lane worktree left on disk for task=9927da28: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b)

## raw — plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] architect_prepass task=1227e21b status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=1227e21b status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=1227e21b founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=1227e21b after 2 attempts -- task PARKED, not dispatched.
[TEST] FAIL: 6: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-partial-close-25598-1787518290.3rSkCe/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=facb93eb status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-partial-close-25598-1787518290.3rSkCe/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=facb93eb class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_warn task=facb93eb class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=facb93eb status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=facb93eb status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=facb93eb status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=facb93eb status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=facb93eb status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=facb93eb founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=facb93eb after 2 attempts -- task PARKED, not dispatched.
[TEST] FAIL: 7/missing: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-partial-close-25598-1787518290.3rSkCe/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=e6492a3e status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-partial-close-25598-1787518290.3rSkCe/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=e6492a3e class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_warn task=e6492a3e class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=e6492a3e status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=e6492a3e status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=e6492a3e status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=e6492a3e status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=e6492a3e status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=e6492a3e founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=e6492a3e after 2 attempts -- task PARKED, not dispatched.
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

## raw — plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none
[leadv2-dispatch-code] quota_precheck_skip model=glm provider=glm task=f2d4299f reason=provider_quota_locked class=provider_refusal
[leadv2-dispatch-code] quota_precheck_skip model=codex provider=codex task=f2d4299f reason=provider_quota_locked class=standdown
[leadv2-dispatch-code] candidate_chain task=f2d4299f arms=sonnet
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=f2d4299f var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=f2d4299f var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=f2d4299f attempt=f2d4299f-1787518357-38670 handle=PID=39057 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] mission-version task=- sig=f2d4299f rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=sonnet task=f2d4299f attempt=f2d4299f-1787518357-38670 handle=PID=39057 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] route_resolved by=router router=v1 model=sonnet task=f2d4299f rule=none reason=resolver_error
route_resolved by=router router=v1 model=sonnet task=f2d4299f rule=none reason=resolver_error
[leadv2-dispatch-code] lane_worktree_left task=f2d4299f founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b
[leadv2-dispatch-code] lane worktree left on disk for task=f2d4299f: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b)
[TEST] FAIL: C3: --task-id AND mission-H1 both present -> reserve row task_id == bound --task-id (got rc=0, row: , out: [leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-ledger-task-id-30032-1787518302.wKtRF7/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=3da0b86c status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-ledger-task-id-30032-1787518302.wKtRF7/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
⚠ PRIMARY ARM BENCHED: glm for 29m (class=provider_refusal, until 2026-08-23T21:21:46Z) — cause: launcher_refusal:quota_gate
[leadv2-dispatch-code] primary_arm_benched provider=glm arm=glm class=provider_refusal minutes=29 until=2026-08-23T21:21:46Z source=launcher_refusal:quota_gate task=3da0b86c
[leadv2-dispatch-code] dispatch_task_bound task=3da0b86c founder_task=N7F-C3-BOUND-ID
[leadv2-dispatch-code] dispatch_classified task=3da0b86c class=non_product reason=explicit_kind_docs kind=docs
s-20260823T205259Z-40002-40003
[registry] rendered /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//dispatch-ledger-task-id-30032-1787518302.wKtRF7/repo/docs/LEAD_V2_STATE.md (4 sessions, history_preserved=False)
[leadv2-dispatch-code] phase_precondition_warn task=3da0b86c class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none
[leadv2-dispatch-code] quota_precheck_skip model=glm provider=glm task=3da0b86c reason=provider_quota_locked class=provider_refusal
[leadv2-dispatch-code] quota_precheck_skip model=codex provider=codex task=3da0b86c reason=provider_quota_locked class=standdown
[leadv2-dispatch-code] candidate_chain task=3da0b86c arms=sonnet
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=3da0b86c var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=3da0b86c var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=3da0b86c attempt=3da0b86c-1787518379-40003 handle=PID=40391 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] mission-version task=N7F-C3-BOUND-ID sig=3da0b86c rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=sonnet task=3da0b86c attempt=3da0b86c-1787518379-40003 handle=PID=40391 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] route_resolved by=router router=v1 model=sonnet task=3da0b86c rule=none reason=resolver_error
route_resolved by=router router=v1 model=sonnet task=3da0b86c rule=none reason=resolver_error
[leadv2-dispatch-code] lane_worktree_left task=3da0b86c founder_task=N7F-C3-BOUND-ID path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b
[leadv2-dispatch-code] lane worktree left on disk for task=3da0b86c: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b)
[TEST] PASS: C4: write-terminal with empty founder + display-name 7th arg -> task_id from display name, founder_task_id empty
[TEST] PASS: C5: write-terminal with 6 args (no display name) -> task_id falls back to founder (back-compat)
[TEST] FAIL: F4: no --task-id collision (got name=[], want OPS-42)
[TEST] FAIL: F4b: identity lookup (got name=[], want 'Totally unrelated record')
[TEST] === 5 passed, 9 failed ===

## raw — plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh (falsification proof) (rc=1)
PASS: (a) park row written before sonnet fallback worker spawn (ordering holds)
PASS: (a) poison fence held
PASS: (b) glm-deferred --list prints the parked sig8
PASS: (b) glm-deferred --list prints 'no deferred glm tasks' when empty
PASS: (c) two credit-empty computations within 24h emit exactly ONE journal line
PASS: (c) a third computation after the stamp ages past 24h emits a second journal line
FAIL: (d) expected sonnet-fallback line missing from rendered artifact -- content=2026-08-20T00:00:00Z [BROAD_STATUS] dispatched=1
⚠ ДОСКА ПУСТА — ничего не выполняется, 0 мин

20:54 · посты н/д · комменты н/д · реплаи н/д

| Линия | Что делает | Состояние |
|---|---|---|
| (живых линий нет) | — | — |

С прошлого удара: +0 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 6 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: (e) shared-cache double refusal: count=2, both distinct sig8s recorded
PASS: (e) park queue holds a row for both distinct sig8s
PASS: (e) run 2's park row carries reason=glm_refused_quota_precheck (benched, never attempted)
PASS: (e2) a repeat bump for an already-present sig8 is a no-op (count stays 1)
PASS: (g) a parked row whose sig8 already landed is reaped, not retried
PASS: (h) a parked row with no usable mission is skipped and stays in the queue (H3)
PASS: (i) a failed retry dispatch leaves the row pending
PASS: (f) real retry-all: new dispatch observed (marker file), 'retried as=', old sig8 reaped from --list
PASS: poison fence held across the suite

================================================
  glm-deferred-ladder suite: FAIL=1
================================================

## raw — plugins/leadv2/scripts/tests/test-glm-first-recovery.sh (falsification proof) (rc=1)
[TEST] PASS: 1: codex unknown + glm ok -> arm=glm, rule=codex_quota_gate_80pct
[TEST] PASS: 1: readings names codex=unknown alongside glm=2% ('glm=2% codex=unknown anthropic=44%')
[TEST] PASS: 2: codex 91% + glm ok -> arm=glm (recovery case at peak)
[TEST] PASS: 3: glm 95% known-hot -> arm=sonnet (R2 guard holds)
[TEST] PASS: 4: codex 44% -> arm=codex, gate does not fire, no readings line
[TEST] PASS: 5: safety row + codex unknown -> arm=sonnet (glm still excluded)
[TEST] PASS: 6: job=review base=codex blocked -> arm=sonnet, never glm
[TEST] FAIL: 7: v1 output drifted (got: $'arm=codex\nrule=codex_fitting_kind\nreason=codex_fitting_mission_kind\ntier=standard\ncodex_quota_blocked=1\ncodex_block_reason=provider_lockout')
[TEST] PASS: 8: happy path -> arm=glm rule=none, no readings line, no glm/anthropic subprocess
[TEST] PASS: 9: journal line carries arm=glm + readings (codex=unknown visible)
[TEST] PASS: 9: absent readings -> arm_resolved line byte-identical to today

=== 10 passed, 1 failed ===

## raw — plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh (falsification proof) (rc=1)
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
TRIPWIRE: paths changed under ${LEADV2_REPO}/plugins or ~/.claude during the run (attribution required in report):
/Users/kostiantyn.vlasenko/.claude
/Users/kostiantyn.vlasenko/.claude/read-once
/Users/kostiantyn.vlasenko/.claude/read-once/session-a0f94283215d9a7f.jsonl
/Users/kostiantyn.vlasenko/.claude/read-once/stats.jsonl
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2
/Users/kostiantyn.vlasenko/.claude/leadv2-state/persona-engine
/Users/kostiantyn.vlasenko/.claude/leadv2-state/repowise-usage.jsonl
/Users/kostiantyn.vlasenko/.claude/.claude.json
/Users/kostiantyn.vlasenko/.claude/backups
/Users/kostiantyn.vlasenko/.claude/backups/.claude.json.backup.1787518549650

## raw — plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh (falsification proof) (rc=1)
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

## raw — plugins/leadv2/scripts/tests/test-leadv2-dispatch-outcome-ledger.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] phase_precondition_warn task=1e60c270 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=1e60c270 status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=1e60c270 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=1e60c270 status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=1e60c270 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=1e60c270 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=1e60c270 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=1e60c270 after 2 attempts -- task PARKED, not dispatched.
[TEST] FAIL: 3: setup — first dispatch failed or fake process died too fast (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-outcome-71031-1787518779.jHeJTp/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=7a89b799 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-outcome-71031-1787518779.jHeJTp/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=7a89b799 class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_warn task=7a89b799 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=7a89b799 status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7a89b799 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7a89b799 status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7a89b799 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7a89b799 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=7a89b799 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=7a89b799 after 2 attempts -- task PARKED, not dispatched.
[TEST] FAIL: 4: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-outcome-71031-1787518779.jHeJTp/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=9ac6c53e status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-outcome-71031-1787518779.jHeJTp/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] dispatch_classified task=9ac6c53e class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_warn task=9ac6c53e class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=9ac6c53e status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=9ac6c53e status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=9ac6c53e status=failed reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=9ac6c53e status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=9ac6c53e status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=9ac6c53e founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=9ac6c53e after 2 attempts -- task PARKED, not dispatched.
[TEST] FAIL: 5: setup — first dispatch or process-death wait failed (rc=3)

[TEST] 0 passed, 4 failed
[TEST] Failures:
  - 1: setup — parallel lanes did not dispatch/die cleanly
  - 3: setup — first dispatch failed or fake process died too fast (rc=3)
  - 4: setup — first dispatch or process-death wait failed (rc=3)
  - 5: setup — first dispatch or process-death wait failed (rc=3)

## raw — plugins/leadv2/scripts/tests/test-leadv2-router-v2-toggle.sh (falsification proof) (rc=1)
FAIL: v1 01: rc=3 line=
FAIL: v1 02: rc=3 line=
FAIL: v1 03: rc=3 line=
FAIL: v1 04: rc=3 line=
FAIL: v1 05: rc=3 line=
FAIL: v1 06: rc=3 line=
FAIL: v1 07: rc=3 line=
FAIL: v1 08: rc=3 line=
FAIL: v1 09: rc=3 line=
FAIL: v1 09: codex decision missing from journal
FAIL: v1 10: rc=3 line=
FAIL: v1 10: ignored failure input not journaled
FAIL: v1 transcript differs from cbca20a
FAIL: v2 stdout label: rc=3 line=
FAIL: v2 journal label missing
FAIL: v2 chain trace: 
FAIL: v2 resolver failure: rc=3 journal=
=== Results: 0 passed, 17 failed ===

## raw — plugins/leadv2/scripts/tests/test-lockout-failure-class.sh (falsification proof) (rc=1)

[leadv2-dispatch-code] route_headroom_chosen task=4aabe789 arm=sonnet after=glm_quota_gate ordered=sonnet headroom={"codex": 0.0, "sonnet": 0.3058221134717109} credits={"codex": {"balance": "0", "has_credits": false}}} scores={"codex":0.0,"sonnet":0.3058221134717109} source=router_v2 unknown=none
[leadv2-dispatch-code] codex_credits_empty since=2026-08-23T21:00:53Z
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=4aabe789 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=4aabe789 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] spawn_failed by=router model=sonnet task=4aabe789 rc=99 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(sonnet) failed rc=99:  POISON: real provider spawn attempted
[leadv2-dispatch-code] ERROR: spawn(sonnet) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-4aabe789.stderr.log

[leadv2-dispatch-code] dispatch_rolled_back reason=all_arms_unavailable task=4aabe789 attempts=glm_refused_quota_gate,sonnet_failed_launcher
[leadv2-dispatch-code] ERROR: all eligible dispatch arms declined or failed for task=4aabe789: glm_refused_quota_gate,sonnet_failed_launcher
PASS: T4a: expired glm record — glm survives the bash precheck (_provider_available)
PASS: T4b: expired codex record — resolver (_lockout_blocked) does not block codex
PASS: T5a: malformed glm record — glm survives the bash precheck, no crash
PASS: T5b: malformed codex record — resolver exits 0, codex not lockout-blocked
FAIL: T6: ordinary failure must not lock out -- lockfile_exists=no output=[leadv2-dispatch-code] dispatch_classified task=580139e2 class=non_product reason=explicit_mission_fast_path kind=unknown
s-20260823T210107Z-27234-27235
[registry] rendered /Users/kostiantyn.vlasenko/Projects/persona-engine/docs/LEAD_V2_STATE.md (19 sessions, history_preserved=False)
[leadv2-dispatch-code] phase_precondition_warn task=580139e2 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none
[leadv2-dispatch-code] candidate_chain task=580139e2 arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=580139e2 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=580139e2 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] arm_refused by=router model=glm task=580139e2 reason=glm_refused_quota_gate
[leadv2-dispatch-code] quota_lockout_recorded provider=glm arm=glm reason=quota_gate class=provider_refusal minutes=1200 strikes=1 source=provider_time
[leadv2-dispatch-code] spawn(glm) refused: quota_gate
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-580139e2.stderr.log

[leadv2-dispatch-code] route_headroom_chosen task=580139e2 arm=sonnet after=glm_quota_gate ordered=sonnet headroom={"codex": 0.0, "sonnet": 0.30583424216437516} credits={"codex": {"balance": "0", "has_credits": false}}} scores={"codex":0.0,"sonnet":0.30583424216437516} source=router_v2 unknown=none
[leadv2-dispatch-code] codex_credits_empty since=2026-08-23T21:01:10Z
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=580139e2 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=580139e2 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] spawn_failed by=router model=sonnet task=580139e2 rc=99 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(sonnet) failed rc=99:  POISON: real provider spawn attempted
[leadv2-dispatch-code] ERROR: spawn(sonnet) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-580139e2.stderr.log

[leadv2-dispatch-code] dispatch_rolled_back reason=all_arms_unavailable task=580139e2 attempts=glm_refused_quota_gate,sonnet_failed_launcher
[leadv2-dispatch-code] ERROR: all eligible dispatch arms declined or failed for task=580139e2: glm_refused_quota_gate,sonnet_failed_launcher
PASS: T7: "PRIMARY ARM BENCHED: glm … class=worker_killed" banner on stderr before the first route line
PASS: T8: strikes escalation — second lock doubles to 20m (base 10, cap 60)

## raw — plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] arm_refused by=router model=glm task=38eb8664 reason=glm_refused_quota_gate
[leadv2-dispatch-code] quota_lockout_recorded provider=glm arm=glm reason=quota_gate class=provider_refusal minutes=30 strikes=1 source=default
[leadv2-dispatch-code] spawn(glm) refused: quota_gate
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-38eb8664.stderr.log

[leadv2-dispatch-code] route_headroom_chosen task=38eb8664 arm=sonnet after=glm_quota_gate ordered=sonnet headroom={"codex": 0.0, "sonnet": 0.3059272103083621} credits={"codex": {"balance": "0", "has_credits": false}}} scores={"codex":0.0,"sonnet":0.3059272103083621} source=router_v2 unknown=none
[leadv2-dispatch-code] codex_credits_empty since=2026-08-23T21:03:23Z
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=38eb8664 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=38eb8664 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] spawn_failed by=router model=sonnet task=38eb8664 rc=99 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(sonnet) failed rc=99:  POISON: real provider spawn attempted
[leadv2-dispatch-code] ERROR: spawn(sonnet) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-38eb8664.stderr.log

[leadv2-dispatch-code] dispatch_rolled_back reason=all_arms_unavailable task=38eb8664 attempts=glm_refused_quota_gate,sonnet_failed_launcher
[leadv2-dispatch-code] ERROR: all eligible dispatch arms declined or failed for task=38eb8664: glm_refused_quota_gate,sonnet_failed_launcher
FAIL: T4: ordinary failure must not lock out -- lockfile_exists=no output=[leadv2-dispatch-code] dispatch_classified task=684382a2 class=non_product reason=explicit_mission_fast_path kind=unknown
s-20260823T210323Z-61887-61888
[registry] rendered /Users/kostiantyn.vlasenko/Projects/persona-engine/docs/LEAD_V2_STATE.md (23 sessions, history_preserved=False)
[leadv2-dispatch-code] phase_precondition_warn task=684382a2 class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none
[leadv2-dispatch-code] candidate_chain task=684382a2 arms=glm,codex,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=684382a2 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=684382a2 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] arm_refused by=router model=glm task=684382a2 reason=glm_refused_quota_gate
[leadv2-dispatch-code] quota_lockout_recorded provider=glm arm=glm reason=quota_gate class=provider_refusal minutes=30 strikes=1 source=default
[leadv2-dispatch-code] spawn(glm) refused: quota_gate
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-684382a2.stderr.log

[leadv2-dispatch-code] route_headroom_chosen task=684382a2 arm=sonnet after=glm_quota_gate ordered=sonnet headroom={"codex": 0.0, "sonnet": 0.3059296026462931} credits={"codex": {"balance": "0", "has_credits": false}}} scores={"codex":0.0,"sonnet":0.3059296026462931} source=router_v2 unknown=none
[leadv2-dispatch-code] codex_credits_empty since=2026-08-23T21:03:26Z
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=684382a2 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=684382a2 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] spawn_failed by=router model=sonnet task=684382a2 rc=99 reason=launcher_nonzero_exit
[leadv2-dispatch-code] ERROR: spawn(sonnet) failed rc=99:  POISON: real provider spawn attempted
[leadv2-dispatch-code] ERROR: spawn(sonnet) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-684382a2.stderr.log

[leadv2-dispatch-code] dispatch_rolled_back reason=all_arms_unavailable task=684382a2 attempts=glm_refused_quota_gate,sonnet_failed_launcher
[leadv2-dispatch-code] ERROR: all eligible dispatch arms declined or failed for task=684382a2: glm_refused_quota_gate,sonnet_failed_launcher
PASS: T5: a seeded codex lockout is precheck-skipped and sonnet is spawned instead
PASS: T7: test-routing-enforcement-p1.sh still fully passes (19 passed, 0 failed)

## raw — plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh (falsification proof) (rc=1)
PASS: T1: retired arm kimi dropped from v2 chain (router=v2), no collapse (rc=0)
PASS: T2: claude-sonnet normalizes to sonnet and survives the filter (chain='sonnet')
PASS: T3: quota-gate reroute drops kimi (router=v2 site=quota_gate), chain=sonnet
PASS: T4: all-retired reroute falls back to the pre-reroute chain (codex+sonnet attempted, no dead lane)
PASS: T5: quota-gate reroute normalizes claude-sonnet -> sonnet (ordered=sonnet)
FAIL: poison fence -- a POISON marker appears in captured output -- a real provider bin was invoked

================================================
  router-v2-retired-arm suite: FAIL=1
================================================

## raw — plugins/leadv2/scripts/tests/test-st2-question-protocol.sh (falsification proof) (rc=3)
[leadv2-dispatch-code] dispatch_classified task=2ae08f9c class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_warn task=2ae08f9c class=Standard missing=plan,gate1,build,test,review,live_verify,close mode=warn
[leadv2-dispatch-code] architect_prepass task=2ae08f9c status=failed reason=failed_rc_1 rc=1
[leadv2-dispatch-code] ERROR: architect prepass failed: [claude-subsession] role file not found in agents/ or roles/: architect
[leadv2-dispatch-code] architect_prepass task=2ae08f9c status=retrying attempt=1/2 reason=failed_rc_1
[leadv2-dispatch-code] architect_prepass task=2ae08f9c status=failed reason=failed_rc_1 rc=1
[leadv2-dispatch-code] ERROR: architect prepass failed: [claude-subsession] role file not found in agents/ or roles/: architect
[leadv2-dispatch-code] architect_prepass task=2ae08f9c status=retrying attempt=2/2 reason=failed_rc_1
[leadv2-dispatch-code] architect_prepass task=2ae08f9c status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=2ae08f9c founder_task_id= reason=no_design_after_2_attempts last_reason=failed_rc_1
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=2ae08f9c after 2 attempts -- task PARKED, not dispatched.

## raw — plugins/leadv2/scripts/tests/test-status-surface.sh (falsification proof) (rc=1)
[TEST] PASS: MP-4: leadv2-status-projects.sh exits 2 on unreadable base
[TEST] PASS: MP-4: leadv2-status-projects.sh exits 0 with empty stdout for 0 qualifying projects
[TEST] 
[TEST] == SWIFTBAR-LIVE-01 round 2: process-truth liveness signals (§2.1) ==
[TEST] PASS: LT-1: dead handle (no other evidence) does not render live
[TEST] PASS: LT-2: alive handle renders live(pid N)
[TEST] PASS: LT-3: handle-less row proven live by argv match (survives a never-recorded handle)
[TEST] PASS: LT-4: live row survives past DONE_TTL (never hidden by the age filter)
[TEST] 
[TEST] == SWIFTBAR-LIVE-01 round 2: worker-row naming from the ledger task_id (§2.4) ==
[TEST] PASS: LN-1: worker row named by its bound task_id, not the sig hash
[TEST] 
[TEST] == SWIFTBAR-R4 (§Fix 1): badge title counts == table header counts ==
[TEST] FAIL: BADGE-1: live-only badge/header agree (title='' header='X X'; line1: )
[TEST] FAIL: BADGE-2: dead-only badge/header agree (title='' header='X X'; line1: )
[TEST] FAIL: BADGE-3: mixed live+dead badge/header agree (title='' header='X X'; line1: )
[TEST] PASS: BADGE-4: multi-project header carries live+dead+projects (lanes (1 live, 0 dead, 0 done в последний час · 2 projects))
grep: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b/plugins/leadv2/scripts/leadv2-status-surface.10s.sh: No such file or directory
[TEST] FAIL: BADGE-5: badge source still carries the LANES_BROKEN fail-safe path
[TEST] 
[TEST] == SWIFTBAR-R4 (§Fix 2): .outcome consumed -- finished != failed ==
[TEST] PASS: OUTCOME-1: .outcome=completed renders done(completed)
[TEST] PASS: OUTCOME-2: .outcome=died-clean renders dead(died-clean)
[TEST] FAIL: OUTCOME-3: differ + red=1 (causes_ok=1 red=X; done='  oc3doneeeeeee                lane   build·done        glm-5.2 5m    done(completed)    oc3donee' dead='  oc3deadeeee                  lane   build·done        glm-5.2 5m    dead(died-clean)   oc3deade' line1='')
[TEST] FAIL: A1: title (🔴=X 🟢=X) vs same-render table row count (🔴=0 🟢=0)
[TEST] PASS: OUTCOME-4: no .outcome -> unknown marker present, not died-clean (got:   oc4unknowneee                lane   build·done        glm-5.2 5m    dead(exit=1)?      oc4unkno)
[TEST] PASS: OUTCOME-5: live row with stale .outcome=completed still renders live
[TEST] 
[TEST] == SWIFTBAR-R4 (§Fix 3): task_id reaches the surface on real dispatches ==
[TEST] PASS: TID-1: task_id survives a terminal row (lane named R4-PROBE-01)
[TEST] PASS: TID-2: terminal row carries task_id == founder_task_id (R4-PROBE-02)
[TEST] PASS: TID-3: quote/backslash task_id -> parseable row, task_id sanitized (got 'R4PROBE03')
[TEST] 
[TEST] == SWIFTBAR-R4 RC-2: every touched script parses under bash 3.2 ==
[TEST] PASS: /bin/bash -n leadv2-dispatch-code.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-ledger.sh
[TEST] PASS: /bin/bash -n leadv2-status-surface.sh
[TEST] FAIL: /bin/bash -n leadv2-status-surface.10s.sh
[TEST] 
[TEST] === 62 passed, 21 failed ===

verdict: RED
