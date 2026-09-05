# builder selfcheck — dispatch-362205f9
generated_at: 2026-09-04T01:09:10Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01
diff_hash: 948dc86f777d6174bc776266775edc9bc531070c53cd861e111dc039a4fd578a
checks: 4   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/glm-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh (falsification proof) (rc=1)
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: run path: GLM_EFFORT=max -> spawn argv carries --effort max (deepthink transport)
[TEST] PASS: dispatch: Heavy -> journal effort=max think=deep source=class_map
[TEST] PASS: dispatch: Heavy -> launcher env GLM_EFFORT=max (deepthink reaches the runner variable)
[TEST] PASS: dispatch: Strategic -> journal effort=max think=deep source=class_map
[TEST] PASS: dispatch: Strategic -> launcher env GLM_EFFORT=max (deepthink reaches the runner variable)
Terminated: 15             ( cd "${REPO}" || exit 97; unset GLM_EFFORT; unset LEADV2_PROJECT_ROOT LEADV2_LANE_WORK_ROOT LEADV2_TASK_ID LEADV2_PARENT_SESSION_ID LEADV2_DISPATCH_LANE_NAME; if [[ -n "${2:-}" ]]; then
    export LEADV2_WORKER_ROLE="$2";
else
    unset LEADV2_WORKER_ROLE;
fi; CLAUDE_PROJECT_ROOT="${REPO}" LEADV2_PROJECT_ROOT="${REPO}" LEADV2_DISPATCH_CACHE_DIR="${D_CACHE}" LEADV2_DISPATCH_E2E_GATE=0 LEADV2_DISPATCH_REVIEW_GATE=0 LEADV2_DISPATCH_ARCHITECT_GATE=0 LEADV2_LANE_SHAPE=off LEADV2_ARM_EARLY_VERDICT_S=0 LEADV2_REQUIRE_PHASES=0 LEADV2_QUOTA_LIVE="${FIXTURE}/dispatch-live.sh" LEADV2_ROUTE_ARBITER_STATE_FILE="${FIXTURE}/dispatch-arb-state" LEADV2_JOURNAL_BIN="${FIXTURE}/journal.sh" JOURNAL_TASK=glm-think-"$1" LEADV2_DISPATCH_GLM_BIN="${FIXTURE}/glm-recorder.sh" LEADV2_DISPATCH_KIMI_BIN=/bin/false LEADV2_DISPATCH_CODEX_BIN=/bin/false LEADV2_DISPATCH_SUBSESSION_BIN=/bin/false LEADV2_WRITESET_PENDING_WINDOW_SEC=0 bash "${DISPATCH}" "think dispatch probe: $1${2:+ role=$2} run=$RANDOM" --kind code --task-class "$1" --writes "src/think-probe-$1-$RANDOM.py" 2>&1 ) > /dev/null 2>&1
[TEST] FAIL: dispatch: Heavy +critic expected effort=max think=deep source=think_deep — got: 
[TEST] FAIL: dispatch: Heavy +critic expected launcher GLM_EFFORT=max — got: 
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh: line 141: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//glm-think-fixture.ElSLJ7/glm-bin-record.txt: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh: line 142: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//glm-think-fixture.ElSLJ7/journal-record.txt: No such file or directory
[TEST] FAIL: dispatch: Standard expected effort=high think=off source=class_map — got: 
[TEST] FAIL: dispatch: Standard expected launcher GLM_EFFORT=high — got: 
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh: line 141: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//glm-think-fixture.ElSLJ7/glm-bin-record.txt: No such file or directory
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh: line 142: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//glm-think-fixture.ElSLJ7/journal-record.txt: No such file or directory
[TEST] FAIL: dispatch: Light expected effort=low think=off source=class_map — got: 
[TEST] FAIL: dispatch: Light expected launcher GLM_EFFORT=low — got: 
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DEEPTHINK-MODE-IS-NOT-WIRED-01/plugins/leadv2/scripts/tests/test-leadv2-dispatch-code.sh: line 205: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T//glm-think-fixture.ElSLJ7/map-extract.sh: No such file or directory
[TEST] FAIL: map: trivial expected 'off class_map' — got: 
[TEST] FAIL: map: light expected 'off class_map' — got: 
[TEST] FAIL: map: bulk expected 'off class_map' — got: 
[TEST] FAIL: map: standard expected 'off class_map' — got: 
[TEST] FAIL: map: heavy expected 'deep class_map' — got: 
[TEST] FAIL: map: strategic expected 'deep class_map' — got: 
[TEST] FAIL: map: Heavy expected 'deep class_map' — got: 
[TEST] FAIL: map: Strategic expected 'deep class_map' — got: 
[TEST] FAIL: map: Light expected 'off class_map' — got: 
[TEST] FAIL: map: bogus-cls expected 'off fallback' — got: 
[TEST] summary: PASS=7 FAIL=16

verdict: RED
