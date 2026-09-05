# builder selfcheck — dispatch-a8ba1b87
generated_at: 2026-09-04T13:17:34Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01
diff_hash: 9e68a479691889cf3ad57d9f4b34c699ea189625ac52dff77b10efb4ac11274d
checks: 25   failed: 5   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 12 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-terminal-deregisters-lane.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-liveness-lies.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface-close-phase.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface-cwd.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-status-surface-handle-identity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-t-core-dispatch-ledger.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-terminal-deregisters-lane.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-lane-liveness-lies.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-status-surface-close-phase.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-status-surface-cwd.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-status-surface-handle-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-t-core-dispatch-ledger.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh (falsification proof) (rc=1)
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=7f38aeb0 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=7f38aeb0 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=7f38aeb0 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=7f38aeb0 after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=7f38aeb0 id=dispatch-7f38aeb0 where=exit_trap
[TEST] FAIL: 7/missing: setup — first dispatch or process-death wait failed (rc=3)
[leadv2-dispatch-code] WARN: foreign project root detected (env=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-partial-close-16805-1788526279.7OH9XS/repo cwd=/Users/kostiantyn.vlasenko/Projects/leadv2) -- using cwd-derived root (FOREIGN-PROJECT-ROOT-GUARD-01)
[leadv2-dispatch-code] project_root_guard task=109dd067 status=foreign_env_overridden env_root=/private/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/dispatch-partial-close-16805-1788526279.7OH9XS/repo cwd_root=/Users/kostiantyn.vlasenko/Projects/leadv2
[leadv2-dispatch-code] lane_plan_missing task=109dd067 reason=source_absent source=/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/109dd067/context.yaml
[leadv2-dispatch-code] task_class=Light route=dispatch source=fallback task=109dd067
[leadv2-dispatch-code] brain_decision task=109dd067 class=Light class_source=computed phases=classify,build,test,review,close reason=no_explicit_class
[leadv2-dispatch-code] dispatch_classified task=109dd067 class=product reason=conservative_default kind=unknown
[leadv2-dispatch-code] phase_precondition_warn task=109dd067 class=Light missing=[leadv2-phase-record.sh] WARN: project root conflict: LEADV2_PROJECT_ROOT=/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//dispatch-partial-close-16805-1788526279.7OH9XS/repo wins over PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2 for this read
missing=classify,build,test,review,close mode=warn
[leadv2-dispatch-code] architect_prepass task=109dd067 status=failed reason=no_lane_writes remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=109dd067 status=retrying attempt=1/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=109dd067 status=failed reason=no_lane_writes remedy=LANE_WRITES:a,b,c
[leadv2-dispatch-code] ERROR: dispatch parked: no declared write set (reason=no_lane_writes)
[leadv2-dispatch-code] ERROR:   remedy: add a 'LANE_WRITES: a,b,c' line to the mission (comma-separated paths, no bullets/prose)
[leadv2-dispatch-code] architect_prepass task=109dd067 status=retrying attempt=2/2 reason=no_lane_writes
[leadv2-dispatch-code] architect_prepass task=109dd067 status=parked reason=no_design_after_2_attempts action=not_dispatched
[leadv2-dispatch-code] prepass_parked task=109dd067 founder_task_id= reason=no_design_after_2_attempts last_reason=no_lane_writes worker_launched=0
[leadv2-dispatch-code] ERROR: architect prepass produced no design for product task=109dd067 after 2 attempts -- task PARKED, not dispatched.
[leadv2-dispatch-code] active_lane_released task=109dd067 id=dispatch-109dd067 where=exit_trap
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
[leadv2-dispatch-code] dispatch_task_bound task=8e194c6e founder_task=N7F-C3-BOUND-ID
[leadv2-dispatch-code] task_class=Light route=dispatch source=fallback task=8e194c6e
[leadv2-dispatch-code] brain_decision task=8e194c6e class=Light class_source=computed phases=classify,build,test,review,close reason=no_explicit_class
[leadv2-dispatch-code] dispatch_classified task=8e194c6e class=non_product reason=explicit_kind_docs kind=docs
[leadv2-dispatch-code] phase_precondition_warn task=8e194c6e class=Light missing=[leadv2-phase-record.sh] WARN: project root conflict: LEADV2_PROJECT_ROOT=/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//dispatch-ledger-task-id-44544-1788526908.ROmvAI/repo wins over PROJECT_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2 for this read
missing=classify,build,test,review,close mode=warn
[leadv2-dispatch-code] protection_derived by=router task=8e194c6e writes=<none> write_class=unknown writes_protected=1 manual_protected=1 effective_protected=1
[leadv2-dispatch-code] arm_resolved job=build arm=glm reason=none complexity=simple duration_class=short
[leadv2-dispatch-code] cost_estimate_recorded task=8e194c6e founder_task=N7F-C3-BOUND-ID arm=glm complexity=simple path=docs/handoff/N7F-C3-BOUND-ID/cost-estimate.yaml
[leadv2-dispatch-code] arm_excluded by=router arm=glm-flash task=8e194c6e reason=protected_path
[leadv2-dispatch-code] arm_excluded by=router arm=freepool task=8e194c6e reason=protected_path
[leadv2-dispatch-code] freepool_floor_mode mode=bulk_only source=yaml test_only=0 task=8e194c6e
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=glm model=glm-5.3 tier=standard effort=high task=8e194c6e reason=cheapest_capable arbiter_pick=glm util_glm=27 util_codex=92 util_claude=0 util_freepool=0 reset_glm=104.81h_live reset_codex=67.60h_live reset_claude=n/a reset_freepool=n/a floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=simple duration_class=short remaining=73.0 reset_in=104.81h reset_basis=live
[leadv2-dispatch-code] candidate_chain task=8e194c6e arms=glm,sonnet
[leadv2-dispatch-code] worker_env_assert arm=glm task=8e194c6e var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=glm task=8e194c6e var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
WARN_UNRESOLVED codebase-memory-mcp
[leadv2-dispatch-code] code_intel_preamble arm=glm task=8e194c6e mode=attached
[leadv2-dispatch-code] effort_applied by=router arm=glm task=8e194c6e effort=low mechanism=flag source=class_map resolved=high
[leadv2-dispatch-code] arm_refused by=router model=glm task=8e194c6e reason=glm_refused_lock_busy
[leadv2-dispatch-code] spawn(glm) refused: lock_busy
[leadv2-dispatch-code] ERROR: spawn(glm) full launcher stderr preserved at /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//leadv2-dispatch-spawn-8e194c6e.stderr.log

[leadv2-dispatch-code] route_fallback from=glm to=sonnet task=8e194c6e reason=glm_refused_lock_busy
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=8e194c6e var=CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS action=ok
[leadv2-dispatch-code] worker_env_assert arm=sonnet task=8e194c6e var=CLAUDE_CODE_ENABLE_TODO_TOOLS action=set value=1
[leadv2-dispatch-code] code_intel_preamble arm=sonnet task=8e194c6e mode=skipped reason=fail_open
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=8e194c6e attempt=8e194c6e-1788527196-22071 handle=PID=99749 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] mission-version task=N7F-C3-BOUND-ID sig=8e194c6e rev=? head="WORKTREE PIN: all edits go in /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees"
worker_spawned model=sonnet task=8e194c6e attempt=8e194c6e-1788527196-22071 handle=PID=99749 LABEL=fake-lane SESSION_ID=fake-session
[leadv2-dispatch-code] route_resolved by=router router=arbiter model=sonnet task=8e194c6e rule=none reason=cheapest_capable
route_resolved by=router router=arbiter model=sonnet task=8e194c6e rule=none reason=cheapest_capable
[leadv2-dispatch-code] model_select_telemetry task=8e194c6e role=worker class=light work_kind=build arm=sonnet model=sonnet fallback_depth=1 floor=none spawn_to_terminal_s=29 terminal=win cause=worker_spawned
[leadv2-dispatch-code] lane_worktree_left task=8e194c6e founder_task=N7F-C3-BOUND-ID path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01
[leadv2-dispatch-code] lane worktree left on disk for task=8e194c6e: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01)
[TEST] PASS: C4: write-terminal with empty founder + display-name 7th arg -> task_id from display name, founder_task_id empty
[TEST] PASS: C5: write-terminal with 6 args (no display name) -> task_id falls back to founder (back-compat)
[TEST] FAIL: F4: no --task-id collision (got name=[], want OPS-42)
[TEST] FAIL: F4b: identity lookup (got name=[], want 'Totally unrelated record')
[TEST] === 5 passed, 9 failed ===

## raw — plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh (falsification proof) (rc=1)
[TEST] PASS: supervise emits log-only lane while registry is empty
[TEST] PASS: silence threshold controls log-only lane verdict
[TEST] PASS: pid-alive silent lane remains silent
[TEST] PASS: pid-alive silent lane is absent from stuck
[TEST] PASS: self-reported provider running + stale log -> silent, not alive
[TEST] PASS: LEADV2_LANE_LIVENESS_V2=0 reproduces exact prior (self-report trusted) behavior
[TEST] PASS: fresh log + no PID + provider cancelled -> alive, terminal status never overrides a fresh log
[TEST] PASS: fresh-cancelled row carries a real age_s
[TEST] PASS: funnel lane with recorded log_path is alive, not dead:no_handoff_dir
[TEST] PASS: funnel lane liveness source is the recorded log_path, not a directory scan
[TEST] PASS: no docs/handoff/FUNNEL-TASK/ directory created for a funnel-dispatched lane
[lane-liveness] WARN: task_id=FUNNEL-GONE has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=FUNNEL-GONE has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: funnel lane with a missing log_path target falls through to the directory scan unchanged
[TEST] PASS: C2: live PID with no artifact floors to silent, not dead
[TEST] PASS: C2 negative: no PID + no artifact stays dead:no_handoff_dir
[TEST] PASS: C1 shape 2: pre-first-write funnel lane resolves starting: via registration grace (dirname scan removed by S1/D3)
[TEST] PASS: C1 shape 4: fanout-lane- sibling dir alone is not lane evidence under the S1 closed ladder
[TEST] PASS: C1 shape 5: docs/leadv2/tasks/<tid>/pulse.md alone is not lane evidence under the S1 closed ladder
[lane-liveness] WARN: task_id=SHAPE6-TASK has no parseable started_at (None) -- age_s is indeterminate, not 0
[lane-liveness] WARN: task_id=SHAPE6-TASK has no parseable started_at (None) -- age_s is indeterminate, not 0
[TEST] PASS: C1 shape 6: sessions.map binding alone is not lane evidence under the S1 closed ladder
[TEST] PASS: D3: 1000s-old stream is silent under --lane
[TEST] PASS: D3 -- --all agrees with --lane for the same 1000s-old lane (no flicker)
[TEST] PASS: D1: pid-less lane past abandon_max ages out to dead, never stays silent forever
[TEST] PASS: D1 -- count_live excludes the abandoned pid-less lane
[TEST] PASS: D1 boundary: ~3570s (< abandon_max 3600) is still silent
[TEST] PASS: D1 boundary: ~3630s (> abandon_max 3600) is dead
[TEST] PASS: D2: fresh started_at + pid null + no artifact resolves starting, not dead
[TEST] PASS: D2 negative: old started_at + no artifact still resolves dead, never starting
[TEST] PASS: SELF-DEADLOCK: fresh prepass child stream is NOT a live signal by default (parent resolves dead)
[TEST] PASS: SELF-DEADLOCK rollback: LEADV2_LANE_PREPASS_LIVE=1 restores the composed-prepass signal
Traceback (most recent call last):
  File "<string>", line 10, in <module>
    assert tokens and tokens[-1] == "+2", ("expected 1 lane token + +2 drop counter, got", tokens, stripped)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError: ('expected 1 lane token + +2 drop counter, got', ['1·?·1s', '+2', '|', 'Test', 'in', '/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//lane-liveness.Q285p8/ladder-repo', '|', 'cc', '20x', '28%·7d/8h50m', '·', 'cc', '5x', '52%·7d/4d6h', '·', 'cx', '8%·wk/2d20h', '·', 'glm', '73%·wk/4d9h'], 'lanes 3/3 1·?·1s +2 | Test in /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//lane-liveness.Q285p8/ladder-repo | cc 20x 28%·7d/8h50m · cc 5x 52%·7d/4d6h · cx 8%·wk/2d20h · glm 73%·wk/4d9h')
[TEST] FAIL: D6 -- degradation ladder dropped a lane
[34mlanes 3/3 1·?·1s +2[0m | [36mTest[0m in [32m/var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//lane-liveness.Q285p8/ladder-repo[0m | [33mcc 20x 28%·7d/8h50m[0m · cc 5x 52%·7d/4d6h · [31mcx 8%·wk/2d20h[0m · glm 73%·wk/4d9h
[TEST-SAFETY] tripwire OK: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01/plugins/leadv2/scripts/leadv2-lane-liveness.sh unchanged (md5 456056613e60dff595f1dab6c900002b before and after)

## raw — plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh (falsification proof) (rc=1)
[TEST] PASS: (a) lead_durable row + live lead pid + stale stream -> dead:silent_1801s_no_process (reclaimable)
[TEST] PASS: (a) pid_source=lead_durable recorded
[TEST] PASS: (b) recycled-pid row (pid alive, birth mismatch) -> dead:silent_1801s_no_process (reclaimable)
[TEST] PASS: (b) pid_identity=mismatch recorded
[TEST] PASS: (b2) malformed birth -> unverified, lane stays silent:1801 (never dead)
[TEST] PASS: (b2) pid_identity=unverified recorded
[TEST] PASS: (c) live lane refuses the re-dispatch (rc 5)
[TEST] PASS: (c) verdict/reason/source byte-identical across the refused attempt (alive/log_fresh)
[TEST] FAIL: (c) probe-read file set changed:
before:
1788527738 21 /tmp/leadv2-lrsd-J6OVSI/target/docs/handoff/dispatch-deadlane01-architect/architect.stream.jsonl
1788527738 36 /tmp/leadv2-lrsd-J6OVSI/target/docs/handoff/dispatch-deadlane01/developer.stream.jsonl
1788527738 194 /tmp/leadv2-lrsd-J6OVSI/state/active.yaml
after:
1788527738 21 /tmp/leadv2-lrsd-J6OVSI/target/docs/handoff/dispatch-deadlane01-architect/architect.stream.jsonl
1788527738 36 /tmp/leadv2-lrsd-J6OVSI/target/docs/handoff/dispatch-deadlane01/developer.stream.jsonl
1788527765 337 /tmp/leadv2-lrsd-J6OVSI/state/active.yaml
[TEST] PASS: (c) refusal journaled (lane_placement_refused in task journal)
[TEST] PASS: (d) live worker row resolves alive
[TEST] PASS: (d) pid_source=worker pid_identity=verified
[TEST] PASS: (d) live worker lane refuses the re-dispatch (rc 5)
[TEST] PASS: (d) journal carries lane_liveness verdict=live signal=stream_fresh
[TEST] PASS: (R2) live --all --json smoke against the real repo root parses (argv unpack in lockstep)

[LANE-REGISTRY-SELF-DEADLOCK-01] passed=14 failed=1

## raw — plugins/leadv2/scripts/tests/test-status-surface-cwd.sh (falsification proof) (rc=1)
[TEST] FAIL: exit 0 from cwd=/ (got rc=127)
[TEST] PASS: non-empty output from cwd=/
[TEST] FAIL: lanes section has >=1 data row (got: bash: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DARK-SUITES-REGRESSED-BY-SELF-REGISTRATION-01/plugins/leadv2/scripts/leadv2-status-surface.10s.sh: No such file or directory)
[TEST] PASS: no forbidden failure-glyph strings present
[TEST] PASS: title line does not start with ⚠️
[TEST] PASS: cwd-invariance: same lane rows from /, $HOME, and /tmp
[TEST] FAIL: cwd-invariance: supervisor row differs by cwd (root='' home='' tmp='')
[TEST] 
[TEST] === 4 passed, 3 failed ===

verdict: RED
