# builder selfcheck — dispatch-2dfefcdd
generated_at: 2026-09-08T11:15:40Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4
diff_hash: 9c7ed999e9acfb29dd9c58616042dd2c9a70abe04cc75a79f3d1a8fde291079e
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a49cbf1665d4/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-finished-state.sh | SKIP (baseline_red) |

## raw — plugins/leadv2/scripts/tests/test-lane-finished-state.sh (lane red, baseline red -- inherited) (rc=1)
[TEST] Test 1: live pid + fresh stream -> alive; not an escalation candidate
[TEST] FAIL: Test 1: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] Test 2: dead pid + recent commit -> finished, no escalation, placement not refused
[TEST] FAIL: Test 2: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] Test 3: dead pid, unborn-HEAD worktree, no deliverable -> dead, escalation raised
[TEST] FAIL: Test 3: verdict=unknown:contradictory_rows removed=True (real death detection must not be disabled by this fix)
[TEST] Test 4: dead pid + recent commit + fresh stream mtime -> still finished, never alive
[TEST] FAIL: Test 4: verdict=unknown:contradictory_rows (must be finished:*, never alive) escalated=False still_present=True
[TEST] Test 6: single OLD commit (older than LEADV2_LANE_FINISHED_WINDOW_S) + no live pid -> dead:*, never finished:*
[TEST] FAIL: Test 6: verdict=unknown:contradictory_rows (must be dead:*, never finished:* or alive/starting)
[TEST] Test 7: registration older than LEADV2_LANE_STARTING_MAX_S (300s default), no pid, no stream -> dead:*, never starting:*
[TEST] FAIL: Test 7: verdict=unknown:contradictory_rows (must be dead:*, never starting:* -- the stuck-starting incident)
[TEST] Test 8: live pid whose cwd is the lane worktree + STALE (but < ABANDON_MAX) stream mtime -> must never read dead or finished
[TEST] FAIL: Test 8: verdict=unknown:contradictory_rows (expected silent:* -- a live worker's lane must never read dead or finished)
[TEST] Test 9: pid alive but recorded birth mismatches observed lstart (pid reuse / an orphan sharing the pid number) -> dead:*, never alive
[TEST] FAIL: Test 9: verdict=unknown:contradictory_rows (must be dead:* -- an alive-but-mismatched pid must never read alive)
[TEST] Test 5a: mutating leadv2-lane-liveness.sh's finished-check must turn verdict non-finished (RED), revert restores it (GREEN)
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got unknown:contradictory_rows) -- fixture broken, mutation gate aborted
[TEST] Test 5b: mutating leadv2-lanes-snapshot.sh's finished-veto must let escalation fire again (RED), revert restores no-escalation (GREEN)
[TEST] PASS: Test 5b: mutation re-enabled escalation on a finished lane (row pruned, RED); revert restores no-escalation (row kept, GREEN)

[TEST] ===================================================================
[TEST] RESULTS: 1 passed, 9 failed
[TEST] FAIL: Test 1: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] FAIL: Test 2: verdict=unknown:contradictory_rows escalated=False still_present=True
[TEST] FAIL: Test 3: verdict=unknown:contradictory_rows removed=True (real death detection must not be disabled by this fix)
[TEST] FAIL: Test 4: verdict=unknown:contradictory_rows (must be finished:*, never alive) escalated=False still_present=True
[TEST] FAIL: Test 6: verdict=unknown:contradictory_rows (must be dead:*, never finished:* or alive/starting)
[TEST] FAIL: Test 7: verdict=unknown:contradictory_rows (must be dead:*, never starting:* -- the stuck-starting incident)
[TEST] FAIL: Test 8: verdict=unknown:contradictory_rows (expected silent:* -- a live worker's lane must never read dead or finished)
[TEST] FAIL: Test 9: verdict=unknown:contradictory_rows (must be dead:* -- an alive-but-mismatched pid must never read alive)
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got unknown:contradictory_rows) -- fixture broken, mutation gate aborted

verdict: GREEN
