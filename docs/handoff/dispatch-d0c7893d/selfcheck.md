# builder selfcheck — dispatch-d0c7893d
generated_at: 2026-09-03T03:28:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWELVE-LINUX-ONLY-SUITES-01
diff_hash: 6e42c90feca93914f67985564732c597bd5e3b79c9765a3d44668515d126e45c
checks: 44   failed: 4   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/codex-lead/statusline/leadv2-tmux-status.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-auto-clear-after-close.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh | 0 |
| bash -n | plugins/leadv2/scripts/codex-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/freepool-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/glm-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/kimi-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-archive-old-tasks.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-event.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fork-session.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-guard-census.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-status-line.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-limits-refresh.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-assert.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-portable-lock.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-state-purge.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.5s.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-sync-contracts-gate.sh | 0 |
| bash -n | plugins/leadv2/tests/test-deploy-merge-blocker-gate.sh | 0 |
| bash -n | plugins/leadv2/tests/test-fanout-lane-detach.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWELVE-LINUX-ONLY-SUITES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-burn-governor.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-codex-quota-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-sync-contracts-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-deploy-merge-blocker-gate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/tests/test-fanout-lane-detach.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh (falsification proof) (rc=1)
[TEST] FAIL: stem-priority-plugins-tests-over-tests (M3)
[TEST] FAIL: suite-green-checks-verdict
[TEST] FAIL: suite-red-baseline-green-fails
[TEST] FAIL: suite-red-baseline-red-skips (H1)
[TEST] FAIL: baseline-unresolved-fails-open (H1)
[TEST] FAIL: child-suite-observes-flag-and-depth (C1)
[TEST] PASS: depth-guard-skips-no-spawn (C1)
[TEST] FAIL: repo-level-runner-never-invoked (C1/decision-A)
[TEST] FAIL: tests-mode-never-skips
[TEST] FAIL: auto-mode-delegates-to-e2e
[TEST] PASS: timeout-wrapper-kills-hung-command (C2)
[TEST] PASS: timeout-wrapper-fast-command-no-hang (C2)
[TEST] PASS: checks-zero-yields-degraded (M1)
[TEST] PASS: bash-n-failure-ignores-baseline-arm
[TEST] PASS: scope-off-write-set-blocks (SCOPE-DISCIPLINE-01)
[TEST] PASS: scope-in-write-set-passes (SCOPE-DISCIPLINE-01)
[TEST] PASS: scope-oversized-diff-blocks (SCOPE-DISCIPLINE-01)

Results: 17 passed(red->green), 21 failed, 0 green-pre-fix, 0 could-not-run
FAIL: broken-sh-blocks-with-reason: post-fix did not pass (rc=1)
FAIL: broken-sh-review-arm-never-spent: post-fix did not pass (rc=1)
FAIL: clean-lane-selfcheck-green: post-fix did not pass (rc=1)
FAIL: broken-py-blocks-with-reason: post-fix did not pass (rc=1)
FAIL: no-arm-skips-selfcheck: post-fix did not pass (rc=1)
FAIL: report-lane-skips-selfcheck: post-fix did not pass (rc=1)
FAIL: falsification-missing-blocks-when-armed (TEST-FALSIFICATION-GATE-01): post-fix did not pass (rc=1)
FAIL: falsification default advisory
FAIL: falsification-present-passes (TEST-FALSIFICATION-GATE-01): post-fix did not pass (rc=1)
FAIL: falsification-forged-marker-failing-rc-blocks (codex r1 HIGH #1): post-fix did not pass (rc=1)
FAIL: falsification-widened-classifier-catches-new-dir (codex r1 MEDIUM #2): post-fix did not pass (rc=1)
FAIL: stem-resolved-from-lane-tests-dir (M3)
FAIL: stem-priority-plugins-tests-over-tests (M3)
FAIL: suite-green-checks-verdict
FAIL: suite-red-baseline-green-fails
FAIL: suite-red-baseline-red-skips (H1)
FAIL: baseline-unresolved-fails-open (H1)
FAIL: child-suite-observes-flag-and-depth (C1)
FAIL: repo-level-runner-never-invoked (C1/decision-A)
FAIL: tests-mode-never-skips
FAIL: auto-mode-delegates-to-e2e

## raw — plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh (falsification proof) (rc=1)
[TEST] PASS: (a) lead_durable row + live lead pid + stale stream -> dead:silent_1800s_no_process (reclaimable)
[TEST] PASS: (a) pid_source=lead_durable recorded
[TEST] PASS: (b) recycled-pid row (pid alive, birth mismatch) -> dead:silent_1800s_no_process (reclaimable)
[TEST] PASS: (b) pid_identity=mismatch recorded
[TEST] PASS: (b2) malformed birth -> unverified, lane stays silent:1800 (never dead)
[TEST] PASS: (b2) pid_identity=unverified recorded
[TEST] PASS: (c) live lane refuses the re-dispatch (rc 5)
[TEST] PASS: (c) verdict/reason/source byte-identical across the refused attempt (alive/log_fresh)
[TEST] FAIL: (c) probe-read file set changed:
before:
1788406045 21 /tmp/leadv2-lrsd-1i3tYT/target/docs/handoff/dispatch-deadlane01-architect/architect.stream.jsonl
1788406045 36 /tmp/leadv2-lrsd-1i3tYT/target/docs/handoff/dispatch-deadlane01/developer.stream.jsonl
1788406045 194 /tmp/leadv2-lrsd-1i3tYT/state/active.yaml
after:
1788406045 21 /tmp/leadv2-lrsd-1i3tYT/target/docs/handoff/dispatch-deadlane01-architect/architect.stream.jsonl
1788406045 36 /tmp/leadv2-lrsd-1i3tYT/target/docs/handoff/dispatch-deadlane01/developer.stream.jsonl
1788406061 1236 /tmp/leadv2-lrsd-1i3tYT/state/active.yaml
[TEST] PASS: (c) refusal journaled (lane_placement_refused in task journal)
[TEST] PASS: (d) live worker row resolves alive
[TEST] PASS: (d) pid_source=worker pid_identity=verified
[TEST] PASS: (d) live worker lane refuses the re-dispatch (rc 5)
[TEST] PASS: (d) journal carries lane_liveness verdict=live signal=stream_fresh
[TEST] PASS: (R2) live --all --json smoke against the real repo root parses (argv unpack in lockstep)

[LANE-REGISTRY-SELF-DEADLOCK-01] passed=14 failed=1

## raw — plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh (falsification proof) (rc=1)

[D1] _pc_process_alive — pid-file liveness (behavioral)
  ok: live meta pid detected as alive
  ok: dead meta pid detected as dead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWELVE-LINUX-ONLY-SUITES-01/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 102: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.hAP0EitbHu/glm-runs/test-handle/pgid: No such file or directory
  FAIL: live child pid in pgid file not detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWELVE-LINUX-ONLY-SUITES-01/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 114: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.hAP0EitbHu/glm-runs/test-handle/.lockref: No such file or directory
  FAIL: live supervisor pid in lock_dir/pid not detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWELVE-LINUX-ONLY-SUITES-01/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 132: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.hAP0EitbHu/glm-runs/test-handle/meta.yaml: No such file or directory
  ok: self pid (60371) excluded — no self-match
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TWELVE-LINUX-ONLY-SUITES-01/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 141: /var/folders/gr/5bbqwwcs6x75mxtky4yqnx400000gq/T/tmp.hAP0EitbHu/glm-runs/test-handle/meta.yaml: No such file or directory
  ok: parent pid (60362) excluded
  ok: no live processes detected as dead

[D1] _pc_reap_worker — kills exact pids (behavioral)
  ok: victim process group from pgid file was reaped (killed)
  ok: reap did not kill self (60371) or parent (60362)
  ok: victim process from lock_dir/pid was reaped
  ok: reap with no live processes is a no-op (rc=0)

[D2] claude-subsession agents_worktree_fallback frontmatter strip
  ok: agents source: frontmatter stripped, body preserved
  ok: source accepts agents_worktree_fallback in frontmatter-strip branch
  ok: worktree fallback derives ROLE_SOURCE=agents_worktree_fallback
  ok: agents_worktree_fallback: frontmatter stripped correctly

[D3] prepass-park uses --no-block (fire-and-forget)
  ok: prepass-park uses --no-block, not blocking --timeout
  ok: prepass_parked journal line present

[D4] empty-status→dead grace guard (behavioral)
  ok: source has meta-existence grace guard before empty-status dead
  ok: old meta (>30s) + empty status → dead-eligible
  ok: fresh meta (<30s) → grace (not dead)

[D5] router_v2 reorder failure journal
  ok: router_v2_reorder_failed journal line present

[PLUGIN-RELIABILITY-01] passed=19 failed=2

## raw — plugins/leadv2/tests/test-fanout-lane-detach.sh (falsification proof) (rc=1)
PASS: extracted _leadv2_new_session_exec from leadv2-fanout.sh (      19 lines)
PASS: fixed: spawned child (pid=81446, used_new_session=true) SURVIVES harness-group SIGTERM
PASS: old (pre-fix pattern): spawned child died with the harness group, reproducing the original bug
PASS: launcher acks (pid file present, live pid) within 100ms -- well under a caller's ack-wait window
PASS: launcher exits 0 on dispatch-code.sh success
PASS: fake worker's stream is still advancing after the launcher process exited
FAIL: active.yaml has no row for test-lane-1 after a successful launch
PASS: launcher exits non-zero on dispatch-code.sh crash (rc=137)
PASS: a 'dead' terminal row was written for the crashed lane -- not silently dropped
PASS: active.yaml has no lingering row for the crashed lane
PASS: extracted _fanout_launch_lane_detached + helpers from leadv2-fanout.sh
PASS: fanout's lane-detach call returns in 4s despite a stuck (never-acking) launcher -- bounded by the ack timeout, not the 840s dispatch-code.sh ceiling
PASS: a 'dead cause=launcher_handoff_timeout' terminal row was written for the stuck lane -- never silently dropped
PASS: the stuck launcher process was killed after the ack timeout
----
PASS=13 FAIL=1

verdict: RED
