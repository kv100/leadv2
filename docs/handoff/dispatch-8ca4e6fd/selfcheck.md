# builder selfcheck — dispatch-8ca4e6fd
generated_at: 2026-09-04T21:25:11Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01
diff_hash: cd990983885168126fa0995cc38f96a37fa528324ae44e162c07bcf0feba7104
checks: 27   failed: 4   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 20 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase-record.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-proof-lib.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-skill-proof.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.5s.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-lane-state.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-complexity-routing.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-effort-routing.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-gets-work.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-mktemp-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-route-arbiter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-routing-canonical-protected-glm.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-claude-profile-select.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-complexity-routing.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-effort-routing.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-gets-work.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-mktemp-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-route-arbiter.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-routing-canonical-protected-glm.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-claude-profile-select.sh (falsification proof) (rc=1)
[TEST] PASS: T21c: no probe ran
[TEST] PASS: T21: exit 0
=== T15: label/expect vs derived identity -> WARN label_mismatch, bucket by identity ===
[TEST] PASS: T15a: label_mismatch warn carries expected + derived
[TEST] PASS: T15b: reported/bucketed identity is the DERIVED one, not the label claim
[TEST] PASS: T15: exit 0 (fail-open)
=== T16: missing .claude.json -> WARN identity_email_unresolved, fail-open ===
[TEST] PASS: T16a: identity_email_unresolved warn
[TEST] PASS: T16b: entry still selectable (fail-open)
[TEST] PASS: T16: exit 0
=== T17: default token expired -> WARN default_token_expired, selection unchanged ===
[TEST] PASS: T17a: default_token_expired warn
[TEST] PASS: T17b: selection itself unchanged
[TEST] PASS: T17: exit 0
=== T18: default credential absent -> WARN default_token_absent, fail-open ===
[TEST] PASS: T18a: default_token_absent warn
[TEST] PASS: T18b: selection proceeds
[TEST] PASS: T18: exit 0
=== T19: WARN lines reach the journal (ISO-prefixed) ===
[TEST] PASS: T19a: journal carries ISO-prefixed same_account WARN
[TEST] PASS: T19b: journal has no token
=== T20 (C2): two no-.claude.json slots, same sub -> distinct buckets, no same_account ===
[TEST] PASS: T20a: distinct quota buckets for two pro/na slots (config-dir key)
[TEST] PASS: T20b: no same_account warn when the email half is unresolved
[TEST] PASS: T20c: both slots warned identity_email_unresolved
[TEST] PASS: T20d: selection still works (fail-open, lowest window wins)
[TEST] PASS: T20: exit 0
=== T21: binding_window (reset-aware) beats blind worst-of-both ===
[TEST] PASS: T21: picks case1 (binding window 20%) over case2 (binding window 90%), reason=binding_window
[TEST] PASS: T21: exit 0
=== T22 (D3, TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01): stale expiresAt does not stop a genuinely live account from winning ===
[TEST] PASS: T22a: WARN fires but does not exclude
[TEST] PASS: T22b: the stale-per-field, live-per-probe account still wins -- the field is not the liveness test
[TEST] PASS: T22: exit 0
=== T23 (D3): same_account still fires when one sibling's expiresAt looks stale ===
[TEST] FAIL: T23a: same_account fires even though one sibling looked expired -- closes the coverage hole -- no match for 'WARN: same_account label=same-fresh label=same-stale identity=team/shared2@fixture\.test' in: [claude-profile-select] WARN: registry line 2: expiresAt_stale label=same-stale identity=team/shared2@fixture.test -- probing live anyway
[claude-profile-select] WARN: same_account label=same-fresh label=same-stale sub=team account=unresolved -- one real account behind two slots
[TEST] FAIL: T23b: both slots stay candidates (fail-open, as with T14) -- no match for '^profile=same-fresh .*candidates=2 ' in: profile=- reason=same_account
[TEST] PASS: T23: exit 0
[TEST] Results: PASS=79 FAIL=2

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
[leadv2-dispatch-code] model_select_telemetry task=b7cc018f role=worker class=light work_kind=diagnose arm=glm model=glm-5.3 fallback_depth=0 floor=none spawn_to_terminal_s=3 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=b7cc018f founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01
[leadv2-dispatch-code] lane worktree left on disk for task=b7cc018f: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01
FAIL: sonnet argv=<no argv captured> dispatch_out=[leadv2-dispatch-code] dispatch_classified task=9929fa65 class=product reason=conservative_default kind=code
[leadv2-dispatch-code] phase_precondition_refused task=9929fa65 class=Heavy missing=classify mode=1
[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: classify
[leadv2-dispatch-code] ERROR:   remedy: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01/plugins/leadv2/scripts/leadv2-phase-record.sh record 9929fa65 classify --artifact <path>
[leadv2-dispatch-code] active_lane_released task=9929fa65 id=dispatch-9929fa65 where=exit_trap rows=1 removed=1 live_worker_kept=0
FAIL: glm dispatch_out=[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm-flash model=glm-5.3-flash tier=standard effort=low task=66966be8 reason=cheapest_capable arbiter_pick=glm-flash util_glm=1 util_codex=1 util_claude=unknown_capped util_freepool=100 reset_glm=5.00h_default_full_period reset_codex=n/a reset_claude=n/a reset_freepool=n/a floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=simple duration_class=short complexity_policy=none remaining=99.0 reset_in=5.00h reset_basis=default_full_period
[leadv2-dispatch-code] candidate_chain task=66966be8 arms=glm-flash,codex
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=66966be8 var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm-flash task=66966be8 var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=glm-flash task=66966be8 mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm-flash task=66966be8 effort=low think=off think_source=class_map mechanism=flag source=class_map resolved=low
[leadv2-dispatch-code] worker_spawned by=router model=glm-flash task=66966be8 attempt=66966be8-1788556814-52834 handle=stub-1788556852-68142
[leadv2-dispatch-code] mission-version task=- sig=66966be8 rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=glm-flash task=66966be8 attempt=66966be8-1788556814-52834 handle=stub-1788556852-68142
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=glm-flash task=66966be8 rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=glm-flash task=66966be8 rule=none reason=cheapest_capable
[leadv2-dispatch-code] model_select_telemetry task=66966be8 role=worker class=light work_kind=diagnose arm=glm-flash model=glm-5.3-flash fallback_depth=0 floor=none spawn_to_terminal_s=2 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=66966be8 founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01
[leadv2-dispatch-code] lane worktree left on disk for task=66966be8: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RECOVER-TWELVE-CONFLICTED-BRANCHES-01
RC=0
FAIL: decision line missing arm+effort: route_resolved by=router router=arbiter model=glm task=b7cc018f rule=none reason=cheapest_capable
SUMMARY: pass=7 fail=4

## raw — plugins/leadv2/scripts/tests/test-phase-precondition.sh (falsification proof) (rc=1)
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

[PHASE-PRECONDITION] pass=79 fail=1

## raw — plugins/leadv2/scripts/tests/test-route-arbiter.sh (falsification proof) (rc=1)
PASS: codex 99% routes to a capable non-codex arm
PASS: all capped refuses all_arms_capped
PASS: protected chain excludes freepool and admits glm
PASS: anti-sticky identical tasks rotate arms
PASS: standard cell deterministically picks glm-flash (cost, not stickiness)
FAIL: fallback output=[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.rs7MNjzvlQ/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=c4c38811 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.rs7MNjzvlQ/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] lane_plan_missing task=c4c38811 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/c4c38811/context.yaml
[leadv2-dispatch-code] cost_estimate_recorded task=c4c38811 founder_task=c4c38811 complexity=simple duration_class=short phase=pre_arm_selection path=docs/handoff/c4c38811/cost-estimate.yaml
[leadv2-dispatch-code] dispatch_classified task=c4c38811 class=product reason=conservative_default kind=code
[leadv2-dispatch-code] dispatch_refused reason=writeset_pending task=c4c38811 blocked_by=b29be2fd age_s=unknown window_s=900 writes=src/x.py
LEADV2_DISPATCH_REFUSED: writeset_pending
PASS: unknown --kind normalizes to code and resolves
PASS: fanout-class-funnel kind resolves an arm
PASS: backlog-pump kind resolves an arm
PASS: broken glm probe (status!=ok) is fail-closed, never selected
PASS: broken-active claude account falls back to the real ok account, not pct=0
SUMMARY: pass=10 fail=1

verdict: RED
