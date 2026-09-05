# builder selfcheck — dispatch-063a910e
generated_at: 2026-09-03T19:14:12Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01
diff_hash: 913b5fb7f15de163685f099c8c142a3680978477e950a9cfe2daeb9acfc59bdd
checks: 5   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-phase-record.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh (falsification proof) (rc=1)
test: 1 new Standard dispatch without plan/gate1 is refused before spawn
  FAIL: case1: new Standard dispatch should exit 3 (got 0, out=[leadv2-dispatch-code] model_select_telemetry task=d82b48ab role=worker class=standard work_kind=build arm=glm-flash model=glm-5.3-flash fallback_depth=0 floor=none spawn_to_terminal_s=2 terminal=win cause=worker_spawned [leadv2-dispatch-code] lane_worktree_left task=d82b48ab founder_task= path=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01 [leadv2-dispatch-code] lane worktree left on disk for task=d82b48ab: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01 )
  FAIL: case1: refused dispatch spawned a worker (glm)
  FAIL: case1: refusal should name plan and gate1 ()
test: 2 approved new Standard dispatch is admitted
  FAIL: case2: approved Standard dispatch should exit 0 (got 3, out=[leadv2-dispatch-code] ERROR: dispatch refused: missing mandatory phases: classify [leadv2-dispatch-code] ERROR:   remedy: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01/plugins/leadv2/scripts/leadv2-phase-record.sh record 245ce565 classify --artifact <path> [leadv2-dispatch-code] active_lane_released task=245ce565 id=dispatch-245ce565 where=exit_trap )
  FAIL: case2: approved dispatch spawned no worker
test: 3 resumed approved Standard lane is admitted
test: 4 caller bootstrap claim cannot override the recorded store
test: 5 project-root mismatch fails loudly and PROJECT_ROOT alone is honoured
test: 5c LEADV2_PROJECT_ROOT alone with no pre-existing dispatch dir is refused

[PHASE-GATE-INVERSION] pass=10 fail=5
[PHASE-GATE-INVERSION] artifacts kept at /tmp/leadv2-phase-gate-jAw5Ne

verdict: RED
