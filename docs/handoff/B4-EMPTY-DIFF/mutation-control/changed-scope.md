# B4 changed-scope report appendix

Result: `timeout -k 10 900 bash tests/run-all.sh --scope changed` returned 124.
The outer foreground wrapper returned 124 too. This is NOT a green broad check.
The checkpoint was removed by the wrapper EXIT trap. The complete outer runner
output is below. Because the outer runner buffers core output, the preserved
core shard snapshots follow separately, explicitly marked as snapshots.
Three core shards finished; shard 2 was still in test-asked-into-void.sh. B4's
suite ran in core shard 3 and printed `RESULT pass=32 fail=0`.

The generated prepass header below appeared during verification in a tracked
file that was a single blank line at the clean starting baseline. Its writer
is leadv2-dispatch-code.sh's prepass cache header block. After all test jobs
ended, an exact-content assertion removed only that header; no user content
or other worktree was restored or overwritten. It is excluded from this diff.

```diff
--- docs/handoff/dispatch-2a3eac7e/architect-prepass.md (baseline)
+++ docs/handoff/dispatch-2a3eac7e/architect-prepass.md (verification side effect)
@@ -1 +1,2 @@
+<!-- leadv2-prepass base_head=d39a8d862b227677b98315eb2430076e126e0c3e generated_at=2026-09-08T15:35:16Z -->
 
```

## tests/run-all.sh raw output

```text
merge_base=fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982
head=2b49cc48438733eb62f79883c6de79e6f5fae154
measured_range=fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982...HEAD
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-arm-advance-real.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-asked-into-void.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-close-gate-nowork-abandoned.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-consumer-symlink-farm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dispatch-product-close-exit-trap.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-dwr-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-empty-writes-autocommit-loud-skip.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-leadv2-merge-safety-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-no-work-terminal.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-02.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-review-arms.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-produced-nothing-cause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-question-delivery-ownership-01.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-report-only-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-body-persist.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-silence-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-single-owner-census.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-silent-arm-index-and-cross-repo.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-stop-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-dod-gate.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-ended-on-wait.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-workflow-bypass-guard-lane.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-review-arm-pool.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh
run-all: 53 selected, scope=changed, select_only=1
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
changed_scope_rc=124
```

## Core shard-0.log snapshot

Captured no later than foreground completion. Partial if no SHARD_RESULT follows.

```text

[CORE-OFFLINE] all plugin shell syntax

[CORE-OFFLINE] product-close scopes a single-repo lane worktree
=== pass 1/2: post-fix (live tree: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts) ===
[TEST][post-fix] PASS C1-tracked-mod
[TEST][post-fix] PASS C2-untracked-new
[TEST][post-fix] PASS C3-clean-anti-rescue
[TEST][post-fix] PASS C4-handoff-only-dirt
[TEST][post-fix] FAIL C5-registered-arm-silent

=== pass 2/2: red-first pre-fix (git archive HEAD) — reds here are EVIDENCE ===
[TEST][pre-fix] PASS C1-tracked-mod
[TEST][pre-fix] PASS C2-untracked-new
[TEST][pre-fix] PASS C3-clean-anti-rescue
[TEST][pre-fix] PASS C4-handoff-only-dirt
[TEST][pre-fix] FAIL C5-registered-arm-silent

Results (post-fix, live tree): 4 passed, 1 failed
FAIL: C5-registered-arm-silent
red-first: 0/4 post-fix-passing cases RED against pre-fix
GREEN-PRE-FIX (not evidence): C1-tracked-mod
GREEN-PRE-FIX (not evidence): C2-untracked-new
GREEN-PRE-FIX (not evidence): C3-clean-anti-rescue
GREEN-PRE-FIX (not evidence): C4-handoff-only-dirt
pre-fix-could-not-run: 0
TRIPWIRE: paths changed under ${LEADV2_REPO}/plugins or ~/.claude during the run (attribution required in report):
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/lib/__pycache__
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/lib/__pycache__/leadv2-glm-policy-resolve.cpython-314.pyc
[CORE-OFFLINE] FAILED: product-close scopes a single-repo lane worktree

[CORE-OFFLINE] plugin reliability (process liveness + role fallback + prepass/reorder signals)

[D1] _pc_process_alive — pid-file liveness (behavioral)
  ok: live meta pid detected as alive
  ok: dead meta pid detected as dead
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 110: /tmp/core-offline-run.U91uB5/suite.a2q8mA/tmp.5fkny3Vw1G/glm-runs/test-handle/pgid: No such file or directory
  FAIL: live child pid in pgid file not detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 122: /tmp/core-offline-run.U91uB5/suite.a2q8mA/tmp.5fkny3Vw1G/glm-runs/test-handle/.lockref: No such file or directory
  FAIL: live supervisor pid in lock_dir/pid not detected
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 140: /tmp/core-offline-run.U91uB5/suite.a2q8mA/tmp.5fkny3Vw1G/glm-runs/test-handle/meta.yaml: No such file or directory
  ok: self pid (59021) excluded — no self-match
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 149: /tmp/core-offline-run.U91uB5/suite.a2q8mA/tmp.5fkny3Vw1G/glm-runs/test-handle/meta.yaml: No such file or directory
  ok: parent pid (37499) excluded
  ok: no live processes detected as dead

[D1] _pc_reap_worker — kills exact pids (behavioral)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 100: _pc_claude_pid: command not found
  ok: victim process group from pgid file was reaped (killed)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 100: _pc_claude_pid: command not found
  ok: reap did not kill self (59021) or parent (37499)
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 100: _pc_claude_pid: command not found
  ok: victim process from lock_dir/pid was reaped
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh: line 100: _pc_claude_pid: command not found
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
[CORE-OFFLINE] FAILED: plugin reliability (process liveness + role fallback + prepass/reorder signals)

[CORE-OFFLINE] builder selfcheck gate (recursion/depth guard, baseline attribution)
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] PASS: bash -n lib/leadv2-builder-selfcheck.sh
[TEST] PASS: /bin/bash -n lib/leadv2-builder-selfcheck.sh (bash 3.2 syntax)
[TEST] RED-then-GREEN: broken-sh-blocks-with-reason (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: broken-sh-review-arm-never-spent (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: clean-lane-selfcheck-green (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: broken-py-blocks-with-reason (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: no-arm-skips-selfcheck (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: report-lane-skips-selfcheck (pre_rc=1 -> post_rc=0)
[TEST] PASS: kill-switch LEADV2_BUILDER_SELFCHECK=0 restores old path (no selfcheck.md, no selfcheck_failed)
[TEST] PASS: scope-kill-switch-byte-restore-and-bypasses (SCOPE-DISCIPLINE-01)
[TEST] RED-then-GREEN: scope-deletion-outside-write-set-blocks (SCOPE-DISCIPLINE-01) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: scope-rename-source-outside-write-set-blocks (SCOPE-DISCIPLINE-01) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: falsification-missing-blocks-when-armed (TEST-FALSIFICATION-GATE-01) (pre_rc=1 -> post_rc=0)
[TEST] PASS: falsification default is advisory (no refusal, row still surfaced)
[TEST] RED-then-GREEN: falsification-present-passes (TEST-FALSIFICATION-GATE-01) (pre_rc=1 -> post_rc=0)
[TEST] PASS: kill-switch LEADV2_TEST_FALSIFICATION_GATE=off restores no-C4 behaviour byte-for-byte
[TEST] RED-then-GREEN: falsification-forged-marker-failing-rc-blocks (codex r1 HIGH #1) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: falsification-widened-classifier-catches-new-dir (codex r1 MEDIUM #2) (pre_rc=1 -> post_rc=0)
[TEST] PASS: stem-resolved-from-lane-tests-dir (M3)
[TEST] PASS: stem-priority-plugins-tests-over-tests (M3)
[TEST] PASS: suite-green-checks-verdict
[TEST] PASS: suite-red-baseline-green-fails
[TEST] PASS: suite-red-baseline-red-skips (H1)
[TEST] PASS: baseline-unresolved-fails-open (H1)
[TEST] PASS: child-suite-observes-flag-and-depth (C1)
[TEST] PASS: depth-guard-skips-no-spawn (C1)
[TEST] PASS: repo-level-runner-never-invoked (C1/decision-A)
[TEST] PASS: tests-mode-never-skips
[TEST] PASS: auto-mode-delegates-to-e2e
[TEST] PASS: timeout-wrapper-kills-hung-command (C2)
[TEST] PASS: timeout-wrapper-fast-command-no-hang (C2)
[TEST] PASS: checks-zero-yields-degraded (M1)
[TEST] PASS: bash-n-failure-ignores-baseline-arm
[TEST] PASS: scope-off-write-set-blocks (SCOPE-DISCIPLINE-01)
[TEST] PASS: scope-in-write-set-passes (SCOPE-DISCIPLINE-01)
[TEST] PASS: scope-oversized-diff-blocks (SCOPE-DISCIPLINE-01)

Results: 38 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run

[CORE-OFFLINE] worker_reason on no_work/dead terminals (LANE-OBSERVABILITY-02)
[TEST] PASS: A1: last result line wins over older assistant text
[TEST] PASS: A2: assistant-text fallback when no result line
[TEST] PASS: A3: 120-char clamp
[TEST] PASS: A4: quote/backslash/newline sanitised (got: He said no and fellnpath C:xy)
[TEST] PASS: A5: codex rollout cwd filter — sibling rollout never wins
[TEST] PASS: A6: glm .out last non-blank line
[TEST] PASS: A7: empty sources -> empty string
[TEST] PASS: A7: empty sources -> rc 0
[TEST] PASS: A9: rollout naming a DIFFERENT dispatch sig8 never wins (no mis-attribution)
[TEST] PASS: A8: LEADV2_WORKER_REASON=0 kill switch
[TEST] PASS: B1a: JSON row carries worker_reason
[TEST] PASS: B1b: journal line gains worker_reason token
[TEST] PASS: B2a: empty worker_reason still an always-present JSON key
[TEST] PASS: B2b: journal line has no worker_reason token when empty
[TEST] PASS: B3: cause readback
[TEST] PASS: C1a: no_work terminal journal line carries worker_reason
[TEST] PASS: C1b: review-gate.md gains worker_reason line
[TEST] PASS: C2: no stream source -> no worker_reason token

[worker-reason-terminal] PASS=18 FAIL=0

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

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] FAIL: R1 pre-fix-equivalent: expected exit 8 + e2e_regression, got rc=5 md=<>
[TEST] FAIL: R1 post-fix: expected non-8 rc + fail_foreign + foreign_files naming B.txt, got rc=5 md=<> flag=<>
[TEST] PASS: R2 (own regression, green pre-fix by design -- both settings still kill it): unchanged
[TEST] PASS: R3 (mixed, green pre-fix by design -- own-wins guard): unchanged, still killed
[TEST] PASS: R4 (empty WRITES_CSV): still kills, now WITH scope: whole_tree_fallback recorded (new-red)
[TEST] PASS: R5 (all green, post-fix): pass, flag stamped scope: lane_writes
[TEST] FAIL: loudness (1/4): missing/mismatched e2e_gate decision line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision writeset_drift task=r6sig001 undeclared=B.txt
tail dispatch-r6sig001 100000
append dispatch-r6sig001 decision review_round_retry_skipped task=r6sig001 round=1 reason=no_mission_file
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=selfcheck_failed terminal=refused cause=selfcheck_failed failed=scope:off_write_set:B.txt checks=1 skipped=1
[TEST] FAIL: loudness (2/4): missing per-suite foreign_failure line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision writeset_drift task=r6sig001 undeclared=B.txt
tail dispatch-r6sig001 100000
append dispatch-r6sig001 decision review_round_retry_skipped task=r6sig001 round=1 reason=no_mission_file
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=selfcheck_failed terminal=refused cause=selfcheck_failed failed=scope:off_write_set:B.txt checks=1 skipped=1
[TEST] FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
[TEST] FAIL: loudness (4/4): sentinel missing for a foreign_failure

[TEST] 5 passed, 6 failed, 0 not run
FAIL: R1 pre-fix-equivalent: expected exit 8 + e2e_regression, got rc=5 md=<>
FAIL: R1 post-fix: expected non-8 rc + fail_foreign + foreign_files naming B.txt, got rc=5 md=<> flag=<>
FAIL: loudness (1/4): missing/mismatched e2e_gate decision line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision writeset_drift task=r6sig001 undeclared=B.txt
tail dispatch-r6sig001 100000
append dispatch-r6sig001 decision review_round_retry_skipped task=r6sig001 round=1 reason=no_mission_file
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=selfcheck_failed terminal=refused cause=selfcheck_failed failed=scope:off_write_set:B.txt checks=1 skipped=1
FAIL: loudness (2/4): missing per-suite foreign_failure line -- append dispatch-r6sig001 decision product_close task=r6sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
append dispatch-r6sig001 decision writeset_drift task=r6sig001 undeclared=B.txt
tail dispatch-r6sig001 100000
append dispatch-r6sig001 decision review_round_retry_skipped task=r6sig001 round=1 reason=no_mission_file
append dispatch-r6sig001 decision review_gate task=r6sig001 status=blocked reason=selfcheck_failed terminal=refused cause=selfcheck_failed failed=scope:off_write_set:B.txt checks=1 skipped=1
FAIL: loudness (3/4): e2e-gate.md missing status: fail_foreign -- 
FAIL: loudness (4/4): sentinel missing for a foreign_failure
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh (scope-selected ad-hoc)
[TEST] PASS: bash and /bin/bash syntax
[TEST] RED-then-GREEN: unregistered-parent-dirt (pre_rc=1 -> post_rc=0)
[TEST] CONTROL-PASSES: registered-unscoped-positive-control (pre_rc=0, post_rc=0)
[TEST] RED-then-GREEN: unregistered-silent-not-advanced (pre_rc=1 -> post_rc=0)

Results: 4 passed(red->green), 0 failed, 0 green-pre-fix, 0 skipped

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-plugin-review-arms.sh (scope-selected ad-hoc)
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
PASS: T3a: stale-tree dispatch exits 4
PASS: T3b: refusal names the stale tree on stderr
PASS: T3c: remedy lands on stderr
PASS: T3d: journal carries dispatch_refused reason=stale_script_tree
PASS: T4a: escape hatch does not refuse (rc=3)
PASS: T4b: escape hatch emits the downgrade warn
PASS: T5(plugin-tree): passes provenance check (rc=0)
PASS: T8(plugin-tree): no 'value=127' (phase-record binary resolves from the plugin tree)
PASS: T5(worktree-style): passes provenance check (rc=0)
PASS: T8(worktree-style): no 'value=127' (phase-record binary resolves from the plugin tree)
PASS: T6a: engine exits 9 and writes review-gate.md
PASS: T6b: status: unreviewed
PASS: T6c: refusal: present
PASS: T6d: resolver_rc: 1 captured
PASS: T6e: resolver_stderr carries the crash line
PASS: T6f: merge_blocked: true
PASS: T6g: artifact ends on merge_blocked: true, not a bare pool: line
PASS: T7: engine review-gate.md field set == lane _pc_write_unreviewed field set (author merge_blocked pool reason refusal resolver_rc resolver_stderr status tried)

plugin-review-arms: 28 pass, 0 fail

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] RED-then-GREEN: undiffable-write-set-bounces-early (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: mixed-write-set-not-bounced (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: unscoped-lane-work-names-offending (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: cross-repo-elsewhere-terminal (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: foreign-repo-landing (pre_rc=1 -> post_rc=0)

Results: 7 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-single-owner-census.sh (scope-selected ad-hoc)
owners found:
  /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/leadv2-dispatch-product-close.sh  [bucket: flag=0]
  /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/leadv2-review-run.sh  [bucket: flag=1]
FAIL: flag=0 bucket invariant broken: count=1, gate-expression-shape-found=no
PASS: flag=1 bucket has exactly one owner: leadv2-review-run.sh
PASS: no unclassified review-orchestration owners

================================================
  review single-owner census: PASS=2 FAIL=1
================================================
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-review-single-owner-census.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-worker-dod-gate.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-dod-gate.sh (incl. 3.2)
[TEST] PASS: bash -n leadv2-mutation-control.sh (incl. 3.2)
[TEST] PASS: check_a: missing report.md -> fail
[TEST] PASS: check_a: report.md without evidence heading -> fail
[TEST] PASS: check_a: committed report.md with Evidence heading -> pass
[TEST] PASS: check_a: brief never mentions report.md -> skip, not fail
[TEST] PASS: check_b: paste-line with no matching fenced section -> fail
[TEST] PASS: check_b: mutation-control paste-line present but no bound artifact -> fail
[TEST] PASS: check_b: hand-written one-line diff_hash artifact (no provenance) -> fail
[TEST] PASS: check_b: real generator-shaped artifact (mutation diff_hash + bound lane_diff_hash) -> pass
[TEST] PASS: check_b: no merge-base resolvable (non-git root) -> undetermined (never a silent pass)
[TEST] PASS: check_c: no tests/run-all.sh in repo -> skip (portability)
[TEST] PASS: check_c: new suite path touched by diff, unregistered -> fail
[TEST] PASS: check_c: suite registered via EXTRA_SUITE_MAP -> pass
[TEST] PASS: check_c: conventional tests/test-*.sh path self-selects, no map row required -> pass
[TEST] PASS: check_d: runtime-state path in diff -> fail
[TEST] PASS: check_d: clean diff -> pass
[TEST] PASS: check_d: deletion-only diff of runtime-state path -> fail
[TEST] PASS: check_d: missing diff_file -> undetermined, never a silent pass
[TEST] PASS: check_d: empty-file creation of a runtime-state path (no ---/+++ lines) -> fail
[TEST] PASS: check_d: 100% rename into a runtime-state path (no ---/+++ lines) -> fail
[TEST] PASS: check_d: mode-only change of a runtime-state path (no ---/+++ lines) -> fail
[TEST] PASS: check_e: external claim w/o evidence:/UNVERIFIED nearby -> dod_note emitted
[TEST] PASS: check_e: claim immediately followed by evidence: -> no note
[TEST] PASS: lv2_dod_gate_run: fully-compliant fixture -> rc=0, out file written
[TEST] PASS: lv2_dod_gate_run: runtime-state violation -> rc=1, reason recorded in out file
[TEST] PASS: lv2_dod_gate_run: unwritable out dir -> cause still named on stdout/stderr, never dod_unknown
[TEST] PASS: mutation-control: mutation applied, suite went red -> exit 0 ok + artifact written
[TEST] PASS: mutation-control: diff_hash is a non-empty applied-mutant hash and lane binding is separate
[TEST] PASS: mutation-control: two different applied mutations produce different diff_hash values
[TEST] PASS: mutation-control: absent anchor -> exit 2 control_not_applied reason=anchor_count
[TEST] PASS: mutation-control: non-green baseline -> exit 2 control_not_applied reason=baseline_not_green
[TEST] PASS: mutation-control: suite does not cover the mutated file -> exit 1 mutant_survived
[TEST] PASS: wiring: LEADV2_REVIEW_ENGINE unset (production default) -> exit 7 before engine split, review-gate.md written
[TEST] PASS: wiring: LEADV2_REVIEW_ENGINE=1 -> identical refusal, exit 7 before engine split
[TEST] test-worker-dod-gate: 35 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/tests/test-review-arm-pool.sh (scope-selected ad-hoc)
PASS: (a) codex-blocked, glm-84 -> reviewer=glm
PASS: (b1) glm=85 -> offered as reviewer
PASS: (b2) glm=95 -> refused, reviewer=opus
PASS: (c) reviewer != author across full arm matrix
PASS: (d) all arms blocked -> reviewer empty, refusal=all_review_arms_unavailable
PASS: (e) codex+glm blocked, anthropic ok -> reviewer=opus
PASS: (e2) product-close launcher passes --model "${arm}" (R1 guard, no hardcoded sonnet; KIMI-CHANNEL-01b renamed inline ${reviewer} to the run_reviewer_arm param ${arm})
FAIL: (f) no --review-pool -> exact 5-line legacy output (got:
arm=sonnet
rule=codex_quota_gate_95pct
reason=codex_quota_gate
tier=
codex_quota_blocked=1
codex_block_reason=quota_read_unknown
readings=glm=unknown codex=unknown anthropic=unknown)
PASS: (g) status: conflict retired from review gate
PASS: (h) status: no_reviewer artifact present
PASS: (k1) codex+glm blocked, kimi up -> reviewer=kimi, kimi:ok: after codex/glm
PASS: (k2) author=kimi -> kimi:author:, reviewer != kimi
PASS: (k3) KIMI_RC=77 -> kimi:blocked:probe, falls through to opus/sonnet
PASS: (k4) safety_touched -> kimi:excluded:safety
PASS: (k5) review_arm_order absent -> default order still includes kimi after glm
PASS: (k6) kimi-bin nonexistent -> kimi:unknown:, not selected (later arm exists)
PASS: (s0) leadv2-review-signals.sh lib present
PASS: (s1) protected-path diff -> kimi:excluded:safety (source=lane_writes matched=agent/safety-gate.py)
PASS: (s2) ordinary path -> protected=false, kimi:ok: present (source=lane_writes)
PASS: (s3) no patterns anywhere -> fail-closed protected=true (source=no_patterns_failclosed)
PASS: (s4) empty lane writes -> fail-closed protected=true (source=no_lane_writes_failclosed)

20 passed, 1 failed
[CORE-OFFLINE] FAILED: plugins/leadv2/tests/test-review-arm-pool.sh (scope-selected ad-hoc)
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=8 fail=5 missing=0
```

## Core shard-1.log snapshot

Captured no later than foreground completion. Partial if no SHARD_RESULT follows.

```text

[CORE-OFFLINE] lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)
[TEST] PASS: bash -n sweep hook + cleanup + lib
[TEST] GREEN-PRE-FIX: P1-registered-lane-kept(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] GREEN-PRE-FIX: P2-arm-open-lane-kept(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] RED-then-GREEN: P3-arm-terminal-lane-swept(hook) (pre_rc=1 -> post_rc=0)
[TEST] GREEN-PRE-FIX: P4-live-pid-lane-kept(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] GREEN-PRE-FIX: P5-young-lane-kept(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] FAIL: P6-orphan-swept-and-journaled(hook) -- post-fix rc=2, expected 0
[TEST] GREEN-PRE-FIX: P7-unreadable-registry-sweeps-nothing(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] RED-then-GREEN: P8-malformed-env-degrades(hook) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: P11-age-from-gitdir-not-dirmtime(hook) (pre_rc=1 -> post_rc=0)
[TEST] GREEN-PRE-FIX: P12-min-age-s-precedence(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] GREEN-PRE-FIX: P1-registered-lane-kept(dead) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] GREEN-PRE-FIX: P2-arm-open-lane-kept(dead) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] RED-then-GREEN: P3-arm-terminal-lane-swept(dead) (pre_rc=1 -> post_rc=0)
[TEST] GREEN-PRE-FIX: P4-live-pid-lane-kept(dead) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] GREEN-PRE-FIX: P5-young-lane-kept(dead) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] FAIL: P6-orphan-swept-and-journaled(dead) -- post-fix rc=2, expected 0
[TEST] GREEN-PRE-FIX: P7-unreadable-registry-sweeps-nothing(dead) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] RED-then-GREEN: P8-malformed-env-degrades(dead) (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: P11-age-from-gitdir-not-dirmtime(dead) (pre_rc=1 -> post_rc=0)
[TEST] GREEN-PRE-FIX: P12-min-age-s-precedence(dead) -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] GREEN-PRE-FIX: P9-failed-removal-never-guts(hook) -- also passed pre-fix; a safety invariant, not evidence of this fix
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh: line 109: /bin/ps: Operation not permitted
[TEST] FAIL: P13-pid-reuse-is-not-live
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh: line 140: /bin/ps: Operation not permitted
[TEST] FAIL: P14-pid-birth-lib-absent-degrades
[TEST] RED-then-GREEN: P10-twin-regex-unchanged

Results: 7 passed(red->green), 4 failed, 13 green-pre-fix
FAIL: P6-orphan-swept-and-journaled(hook): post-fix rc=2
FAIL: P6-orphan-swept-and-journaled(dead): post-fix rc=2
FAIL: P13-pid-reuse-is-not-live
FAIL: P14-pid-birth-lib-absent-degrades
[CORE-OFFLINE] FAILED: lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)

[CORE-OFFLINE] plugin reliability-02 (zombie-reaper: run_dir arg + group signaling + ordering + TASK)
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=PLUGIN-RELIABILITY-02 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=PLUGIN-RELIABILITY-02 status=waiting_worker author=glm handle=timeout-reap-proof waited=0s
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=PLUGIN-RELIABILITY-02 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] review_gate task=PLUGIN-RELIABILITY-02 status=blocked reason=worker_timeout terminal=dead cause=timeout
ok: real close-timeout reap killed setsid group child (gate rc=5)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-arm-advance-real.sh (scope-selected ad-hoc)
FAIL: expected two worker_spawned lines, got 1
lane_plan_missing task=f3ea32c6 reason=source_absent source=/tmp/core-offline-run.U91uB5/suite.nRRY6q/armfix.Gbkwlr/repo/docs/handoff/f3ea32c6/context.yaml carried_siblings=0
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
worker_spawned by=router model=freepool task=f3ea32c6 attempt=f3ea32c6-1788881306-64616 handle=armfix-freepool
mission-version task=- sig=f3ea32c6 rev=? head="## Delegation (nested agents) You may spawn nested subagents for bulk reads, censuses, or "
product_close task=f3ea32c6 status=spawned author=freepool
route_resolved by=router router=arbiter model=freepool task=f3ea32c6 rule=none reason=forced
model_select_telemetry task=f3ea32c6 role=worker class=standard work_kind=code arm=freepool model=freepool fallback_depth=0 floor=none spawn_to_terminal_s=6 terminal=win cause=worker_spawned
lane_worktree_left task=f3ea32c6 founder_task= path=/tmp/core-offline-run.U91uB5/suite.nRRY6q/armfix.Gbkwlr/repo/.claude/worktrees/f3ea32c6
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-arm-advance-real.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dirty-lane-never-lands.sh (scope-selected ad-hoc)
PASS: terminal funnel and CLOSE gate downgrade worker dirt, preserve the dirty-death pin, keep pass_unlanded non-transitive, honor the rollback switch, and permit bootstrap-only lanes

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: R1: rc=124 classifies as status:unknown reason:e2e_timeout, exit 5 (not 8/e2e_regression)
[TEST] PASS: R1: journal records verdict=timeout rc=124
[TEST] PASS: R1: ledger terminal is parked/e2e_timeout, not dead/e2e_regression
[TEST] PASS: R1: worker's write survives as a checkpoint commit despite the timeout terminal
[TEST] PASS: R2 (negative control): a real rc=1 failure still classifies as e2e_regression, exit 8
[TEST] PASS: R2: ledger terminal is still dead/e2e_regression for a genuine failure
[TEST] PASS: R3: standalone phase-8 gate records timeout as unknown, exit 5, and writes no pass sentinel
[TEST] PASS: R3: standalone phase-8 journal records verdict=timeout rc=124

[TEST] 9 passed, 0 failed, 0 not run

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-dispatch-code.sh
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: bash -n leadv2-fanout-lane-launcher.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] GREEN-PRE-FIX: C1-glm -- passed against HEAD too (pre_rc=0)
[TEST] GREEN-PRE-FIX: C1-codex -- passed against HEAD too (pre_rc=0)
[TEST] RED-then-GREEN: C1-sonnet (pre_rc=1 -> post_rc=0)
[TEST] GREEN-PRE-FIX: C2 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: C2-b -- post-fix rc=1, expected 0
[TEST] FAIL: C3 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: H4 -- passed against HEAD too (pre_rc=0)
[TEST] GREEN-PRE-FIX: H5 -- passed against HEAD too (pre_rc=0)
[TEST] GREEN-PRE-FIX: H6 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: M7 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: M8 -- passed against HEAD too (pre_rc=0)
[TEST] FAIL: L11 -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: L12 -- passed against HEAD too (pre_rc=0)

Results: 5 passed(red->green), 4 failed, 8 green-pre-fix, 0 could-not-run
red=5 green-pre-fix=8 could-not-run=0
FAIL: C2-b: post-fix did not pass (rc=1)
FAIL: C3: post-fix did not pass (rc=1)
FAIL: M7: post-fix did not pass (rc=1)
FAIL: L11: post-fix did not pass (rc=1)
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-produced-nothing-cause.sh (scope-selected ad-hoc)
PASS: a quota refusal is quota_denied, not the model's failure
PASS: a lane with no task dir is no_artifacts_delivered
PASS: an arm that ran with its artifacts present is empty_output
PASS: the three events yield three distinct non-empty words (quota_denied / no_artifacts_delivered / empty_output)
PASS: another arm's quota refusal is not borrowed as this arm's cause
[PRODUCED-NOTHING-CAUSE] pass=5 fail=0

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh (scope-selected ad-hoc)
PASS: bash -n clean (leadv2-dispatch-product-close.sh)
PASS: T1: resolver crash -> review-gate.md is loud (refusal/resolver_rc/resolver_stderr/merge_blocked all populated)
PASS: T1 detail: resolver_stderr: path contains the resolver's actual stderr text
PASS: T2: review_pool_resolve ledger line present on the successful path too

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-dispatch-product-close.sh
[TEST] PASS: /bin/bash -n leadv2-dispatch-product-close.sh (bash 3.2 syntax)
[TEST] RED-then-GREEN: verdict-recovered-from-persisted-body (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: no-verdict-marker-names-persisted-body (pre_rc=1 -> post_rc=0)

Results: 4 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh (scope-selected ad-hoc)
PASS: Sonnet launcher records the finalizer PID
PASS: continuation path normalizes raw handles
PASS: Sonnet raw handle reduces to PID
PASS: close gate waits while finalizer is alive
PASS: close gate finishes after .finalized
PASS: pointer-moved close gate waits on exact PID run directory
PASS: pointer-moved close gate finishes after exact run finalization
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/tests/test-worker-outlives-terminal-state.sh: line 186: 15521 Killed: 9                  sleep 30
PASS: timeout close exits blocked
PASS: timeout terminal has no live model or finalizer
PASS: timeout terminal emitted after reaping
PASS: recorded terminal leaves worker and finalizer gone within 15s (9s)
test-worker-outlives-terminal-state: 11 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/tests/test-review-pool-unknown-is-not-unavailable.sh (scope-selected ad-hoc)
PASS: GLM selected after quota check: actual='glm' expected='glm'
PASS: GLM quota calls before selection: actual=1 expected=1
PASS: resolver excludes author codex: actual='fable' expected='fable'
PASS: resolver excludes author glm: actual='fable' expected='fable'
PASS: resolver excludes author fable: actual='opus' expected='opus'
PASS: resolver excludes author opus: actual='fable' expected='fable'
PASS: resolver excludes author sonnet: actual='fable' expected='fable'
PASS: known hot pool has no reviewer: actual='' expected=''
PASS: locked unknown pool has no reviewer: actual='' expected=''
PASS: consumer glm:unknown:quota_checked author=codex admission rc: actual=1 expected=1
PASS: consumer kimi:unknown:quota_checked author=codex admission rc: actual=1 expected=1
PASS: consumer fable:unknown: author=codex admission rc: actual=1 expected=1
PASS: consumer fable:unknown:quota_checked author=fable admission rc: actual=1 expected=1
PASS: consumer sonnet:ok:10 author=sonnet admission rc: actual=1 expected=1
PASS: consumer fable:unknown:quota_checked author=codex admission rc: actual=0 expected=0
PASS: close codex launcher identities: actual=['glm', 'fable'] expected=['glm', 'fable']
PASS: close codex reviewer identity: actual='fable' expected='fable'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close codex launcher identities: actual=['glm', 'fable', 'opus'] expected=['glm', 'fable', 'opus']
PASS: close codex reviewer identity: actual='opus' expected='opus'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close codex launcher identities: actual=['glm', 'fable', 'opus', 'sonnet'] expected=['glm', 'fable', 'opus', 'sonnet']
PASS: close codex reviewer identity: actual='sonnet' expected='sonnet'
PASS: close codex gate status: actual='pass' expected='pass'
PASS: close codex exit: actual=0 expected=0
PASS: close codex GLM quota checked: actual=True expected=True
PASS: close fable launcher identities: actual=['glm', 'opus'] expected=['glm', 'opus']
PASS: close fable reviewer identity: actual='opus' expected='opus'
PASS: close fable gate status: actual='pass' expected='pass'
PASS: close fable exit: actual=0 expected=0
PASS: close fable GLM quota checked: actual=True expected=True
PASS: close sonnet launcher identities: actual=['glm', 'fable'] expected=['glm', 'fable']
PASS: close sonnet reviewer identity: actual='fable' expected='fable'
PASS: close sonnet gate status: actual='pass' expected='pass'
PASS: close sonnet exit: actual=0 expected=0
PASS: close sonnet GLM quota checked: actual=True expected=True
RESULT: 0 failures
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=8 fail=3 missing=0
```

## Core shard-2.log snapshot

Captured no later than foreground completion. Partial if no SHARD_RESULT follows.

```text

[CORE-OFFLINE] product-close resumes a died-with-work lane once
[TEST] PASS: stub launcher invoked exactly once
[TEST] PASS: stub argv contains bg and --cwd
[TEST] PASS: .dwr-resume-attempted exists
[TEST] PASS: journal has dwr_resume new_run=260803-180000-resume01
[TEST] PASS: gating ran (review.diff created)
[TEST] PASS: stub launcher NOT invoked when marker present
[TEST] PASS: journal has new_run=skipped reason=already_attempted
[TEST] PASS: gating still ran with marker present
[TEST] PASS: stub NOT invoked for outcome=completed
[TEST] PASS: outcome=completed has no dwr_resume journal line
[TEST] PASS: stub NOT invoked for outcome=died-clean
[TEST] PASS: outcome=died-clean has no dwr_resume journal line
[TEST] PASS: journal has blocked_by_gate rc=2
[TEST] PASS: gating still ran after gate refusal
[TEST] PASS: marker written despite gate refusal
[TEST] PASS: kimi: stub launcher invoked once
[TEST] PASS: kimi: journal has dwr_resume new_run=260803-180000-kimires
[TEST] PASS: kimi: gating ran
[TEST] PASS: kill switch: stub NOT invoked
[TEST] PASS: kill switch: no dwr_resume journal line

=== 20 passed, 0 failed ===

[CORE-OFFLINE] question delivery ownership
[TEST] === QUESTION-DELIVERY-OWNERSHIP-01 test suite ===

[TEST] PASS: Syntax: leadv2-ask.sh OK
[TEST] PASS: Syntax: leadv2-reply-router.sh OK
[TEST] PASS: Syntax: leadv2-dispatch-product-close.sh OK
[TEST] Test (a): ask stamps owner_session / owner_task / asked_repo
[TEST] PASS: Test (a): owner_session=sess-alpha-123 owner_task=TASK-OWNER asked_repo=link
[TEST] Test (b1): router refuses young foreign answer (exit 6)
[TEST] PASS: Test (b1): young foreign answer refused (exit 6), owner printed
[TEST] Test (b2): router allows old foreign answer (age >= threshold)
[TEST] PASS: Test (b2): old foreign answer allowed and recorded
[TEST] Test (b3): router allows own session to answer (regardless of age)
[TEST] PASS: Test (b3): own session answered immediately (no age gate)
[TEST] Test (b4): --force overrides young foreign refusal
[TEST] PASS: Test (b4): --force overrode refusal and logged FORCE_FOREIGN
[TEST] Test (c): old-row (no owner fields) tolerated by router
[TEST] PASS: Test (c): old-row without owner fields answered (no refusal)
[TEST] Test (d): _pc_emit_pending_questions emits for own task, not others
<string>:3: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
[TEST] PASS: Test (d): emitted question_pending for own task qid, not other task's

[TEST] === Results: PASS=10 FAIL=0 ===
[TEST] All tests passed.

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

[CORE-OFFLINE] silent-arm commits-ahead + live-worker guard (GATE-FALSE-SILENT-01)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case A: a committed lane (clean worktree) is NOT classified arm_produced_nothing
[TEST] PASS: Case A: no arm_advance decision for a committed lane
[TEST] PASS: Case B: absent stream is NOT classified arm_produced_nothing
[TEST] PASS: Case C: fresh stream is NOT classified arm_produced_nothing
[TEST] PASS: Case D: genuinely silent arm still classified arm_produced_nothing
[TEST] PASS: Case D: ledger row is no_work/arm_produced_nothing
[TEST] PASS: Case D: exactly one arm_advance decision line
[TEST] PASS: Case D: .arm-advanced-glm marker present
[TEST] PASS: Case E: unresolvable-base lane is NOT classified arm_produced_nothing
[TEST] PASS: Case E: degradation line emitted for unresolvable base
[TEST] PASS: Case F: prove-zero linked worktree with unmoved HEAD IS classified arm_produced_nothing
[TEST] PASS: Case F: no silent_probe_base_unresolved line for a provably-zero lane
[TEST] PASS: Case G: linked worktree that committed is NOT classified arm_produced_nothing
[TEST] PASS: Case G: degradation line emitted (unresolved) OR a resolved non-zero count logged

[TEST] 15 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-asked-into-void.sh (scope-selected ad-hoc)
[TEST] PASS: trailing '?' detected
[TEST] PASS: normal result not flagged
[TEST] PASS: fullwidth '？' detected
[TEST] PASS: empty result not flagged
```

## Core shard-3.log snapshot

Captured no later than foreground completion. Partial if no SHARD_RESULT follows.

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
[TEST] PASS: positive control died-with-work resume remains green
[TEST] RESULT: pass=8 fail=1 skip=0
[CORE-OFFLINE] FAILED: parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)

[CORE-OFFLINE] review body persist (opus/sonnet materialisation + body_lost guard)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: /bin/bash 3.2 -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Test (a) deliverable: exit 0
[TEST] PASS: Test (a): review-sonnet.md has both contract lines
[TEST] PASS: Test (a): review-sonnet.md is 688 bytes (full body materialised, not 97)
[TEST] PASS: Test (a): review-sonnet.md contains the numbered findings prose
[TEST] PASS: Test (a2) stream-fallback: exit 0
[TEST] PASS: Test (a2): review-sonnet.md has REVIEW_VERDICT from stream transcript
[TEST] PASS: Test (a2): review-sonnet.md is 413 bytes (stream body recovered)
[TEST] PASS: Test (b) body_lost: exit 6
[TEST] PASS: Test (b): review-gate.md status=blocked reason=review_body_lost
[TEST] PASS: Test (c) glm-regression: exit 0
[TEST] PASS: Test (c): review-gate.md status=pass — guard did not trip on healthy glm arm

[TEST] 13 passed, 0 failed

[CORE-OFFLINE] codex-dead review reroute (QUOTA-GATE-PARITY-01)
[TEST] PASS: bash -n clean (lib/leadv2-review-reroute-note.sh)
[TEST] PASS: py_compile clean (lib/leadv2-glm-policy-resolve.py)
[TEST] PASS: resolver: codex limit_reached (null pct) -> codex:blocked:100 in pool
[TEST] PASS: resolver: reviewer rerouted away from dead codex (reviewer=glm)
[TEST] PASS: reroute-note: emits codex_dead_reroute naming dead codex + new reviewer
[TEST] PASS: reroute-note: exactly one line
[TEST] PASS: reroute-note: silent when codex is the (healthy) reviewer
[TEST] PASS: leadv2-review-run.sh: sources + calls the shared reroute-note helper
[TEST] PASS: leadv2-dispatch-product-close.sh: sources + calls the shared reroute-note helper
[TEST] PASS: bash -n clean (leadv2-review-run.sh)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)

=== 11 passed, 0 failed ===

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-close-gate-nowork-abandoned.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case A: 3 commits ahead of origin/main are NOT stamped no_work/empty_diff
[TEST] PASS: Case A: no empty_diff ledger row for the lane with real work ahead of main
[TEST] PASS: Case B: a lane whose work genuinely landed in main is still stamped empty_diff
[TEST] PASS: Case B: ledger row is no_work/empty_diff for the landed lane

[TEST] 5 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: Case 1: exits 5 (falls through to the existing empty_diff terminal)
[TEST] PASS: Case 1: absent stream is NOT classified as arm_produced_nothing
[TEST] PASS: Case 1: ledger row is no_work/empty_diff (existing path, not the silent-arm path)
[TEST] PASS: Case 1: no arm_advance decision for an absent stream
[TEST] PASS: Case 2: review-gate.md not arm_produced_nothing (assistant events present)
[TEST] PASS: Case 2: ledger row lands as before (regression lock, both gates off)
[TEST] PASS: Case 3: fresh (within growth window) stream falls through as NOT silent
[TEST] PASS: Case 3: existing empty-diff path still produces reason: no_work
[TEST] PASS: Case 4: stale stream + clean worktree classified as silent
[TEST] PASS: Case 5: no arm_produced_nothing when arm not registered (empty_diff path owns it)
[TEST] PASS: Case 5: no arm_advance decision without arm registration

[TEST] 12 passed, 0 failed

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
TRIPWIRE: paths changed under ${LEADV2_REPO}/plugins or ~/.claude during the run (attribution required in report):
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/leadv2-dispatch-ledger.sh
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/lib/__pycache__
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B4-EMPTY-DIFF/plugins/leadv2/scripts/lib/__pycache__/leadv2-launch-registry.cpython-314.pyc
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n leadv2-merged-worktree-sweep.sh
[TEST] FAIL: merged-lane-with-orchestration-dirt-is-swept -- post-fix rc=1, expected 0
[TEST] GREEN-PRE-FIX: real-uncommitted-work-is-never-swept -- also passed pre-fix; a safety invariant, not evidence of this fix
[TEST] FAIL: unmerged-lane-is-never-swept -- post-fix rc=1, expected 0
[TEST] RED-then-GREEN: newborn-lane-age-0-is-never-swept (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: untracked-handoff-deliverable-survives-sweep (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: staged-handoff-not-reverted-by-sweep (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: ignored-handoff-not-removed-through (pre_rc=1 -> post_rc=0)
[TEST] GREEN-PRE-FIX: exclusion-regex-matches-its-twin -- also passed pre-fix; a safety invariant, not evidence of this fix

Results: 4 passed(red->green), 2 failed, 2 green-pre-fix
FAIL: merged-lane-with-orchestration-dirt-is-swept: post-fix rc=1
FAIL: unmerged-lane-is-never-swept: post-fix rc=1
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh (scope-selected ad-hoc)
[TEST] PASS: Test 1 (fallthrough_to_second_arm): exit 0
[TEST] PASS: Test 1: review-gate.md status=pass -- second arm's PASS verdict was recorded
[TEST] FAIL: Test 1: no arm_no_verdict fallthrough line for sonnet -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t1sig001 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t1sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t1sig001 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t1sig001 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t1sig001 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t1sig001 source=plugin
[leadv2-dispatch-product-close] review_signals task=t1sig001 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t1sig001 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t1sig001 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t1sig001 status=ran author=codex reviewer=glm verdict=PASS diff=e1a23188 review_source=stream verdict_source=marker ledger_rc=0
[TEST] PASS: Test 1: journal confirms the RECORDED verdict came from glm (the second arm), not sonnet
[TEST] PASS: Test 2 (empty_output_falls_through): exit 0
[TEST] PASS: Test 2: review-gate.md status=pass -- empty first arm was NOT mistaken for a pass, glm's PASS was recorded instead
[TEST] FAIL: Test 2: no arm_no_verdict fallthrough line for empty sonnet output -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t2sig002 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t2sig002 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t2sig002 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t2sig002 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t2sig002 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t2sig002 source=plugin
[leadv2-dispatch-product-close] review_signals task=t2sig002 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t2sig002 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t2sig002 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t2sig002 status=ran author=codex reviewer=glm verdict=PASS diff=4030b12f review_source=stream verdict_source=marker ledger_rc=0
[TEST] PASS: Test 3 (pool_exhausted_dies): exit 6
[TEST] PASS: Test 3: review-gate.md status=blocked reason=no_verdict_marker after both arms exhausted
[TEST] FAIL: Test 3: terminal journal line missing full tried= list -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t3sig003 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t3sig003 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t3sig003 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t3sig003 source=plugin
[leadv2-dispatch-product-close] review_signals task=t3sig003 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t3sig003 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t3sig003 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t3sig003-review/review-glm.md bytes=212
[TEST] FAIL: Test 3: missing one or both per-arm arm_no_verdict lines -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t3sig003 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t3sig003 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t3sig003 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t3sig003 source=plugin
[leadv2-dispatch-product-close] review_signals task=t3sig003 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t3sig003 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t3sig003 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t3sig003-review/review-glm.md bytes=212
[TEST] FAIL: Test 4: expected exit 0, got 6 -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t4sig004 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t4sig004 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t4sig004 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t4sig004 source=plugin
[leadv2-dispatch-product-close] review_signals task=t4sig004 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t4sig004 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t4sig004 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t4sig004-review/review-glm.md bytes=212
[TEST] FAIL: Test 4: review-gate.md wrong -- status: blocked
reason: no_verdict_marker
body: docs/handoff/dispatch-t4sig004-review/review-glm.md
bytes: 212
[TEST] FAIL: Test 4: glm was invoked despite sonnet passing -- /tmp/core-offline-run.U91uB5/suite.yTS3QM/review-arm-no-verdict-test.ITaxSW/t4/root/docs/handoff/dispatch-t4sig004/review-glm.md exists (Reviewing the diff now, this looks like a reasonable change overall and the structure is sound.
Still going through the files one by one to check for edge cases before writing up findings.
[Tool use interrupted])
[TEST] FAIL: Test 4: unexpected fallthrough journal line on a first-arm pass -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t4sig004 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t4sig004 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t4sig004 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t4sig004 source=plugin
[leadv2-dispatch-product-close] review_signals task=t4sig004 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t4sig004 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t4sig004 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t4sig004-review/review-glm.md bytes=212

[TEST] 7 passed, 8 failed
FAIL: Test 1: no arm_no_verdict fallthrough line for sonnet -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t1sig001 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t1sig001 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t1sig001 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t1sig001 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t1sig001 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t1sig001 source=plugin
[leadv2-dispatch-product-close] review_signals task=t1sig001 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t1sig001 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t1sig001 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t1sig001 status=ran author=codex reviewer=glm verdict=PASS diff=e1a23188 review_source=stream verdict_source=marker ledger_rc=0
FAIL: Test 2: no arm_no_verdict fallthrough line for empty sonnet output -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t2sig002 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t2sig002 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t2sig002 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t2sig002 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t2sig002 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t2sig002 source=plugin
[leadv2-dispatch-product-close] review_signals task=t2sig002 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t2sig002 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t2sig002 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t2sig002 status=ran author=codex reviewer=glm verdict=PASS diff=4030b12f review_source=stream verdict_source=marker ledger_rc=0
FAIL: Test 3: terminal journal line missing full tried= list -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t3sig003 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t3sig003 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t3sig003 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t3sig003 source=plugin
[leadv2-dispatch-product-close] review_signals task=t3sig003 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t3sig003 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t3sig003 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t3sig003-review/review-glm.md bytes=212
FAIL: Test 3: missing one or both per-arm arm_no_verdict lines -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t3sig003 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t3sig003 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t3sig003 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t3sig003 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t3sig003 source=plugin
[leadv2-dispatch-product-close] review_signals task=t3sig003 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t3sig003 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t3sig003 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t3sig003 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t3sig003-review/review-glm.md bytes=212
FAIL: Test 4: expected exit 0, got 6 -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t4sig004 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t4sig004 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t4sig004 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t4sig004 source=plugin
[leadv2-dispatch-product-close] review_signals task=t4sig004 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t4sig004 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t4sig004 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t4sig004-review/review-glm.md bytes=212
FAIL: Test 4: review-gate.md wrong -- status: blocked
reason: no_verdict_marker
body: docs/handoff/dispatch-t4sig004-review/review-glm.md
bytes: 212
FAIL: Test 4: glm was invoked despite sonnet passing -- /tmp/core-offline-run.U91uB5/suite.yTS3QM/review-arm-no-verdict-test.ITaxSW/t4/root/docs/handoff/dispatch-t4sig004/review-glm.md exists (Reviewing the diff now, this looks like a reasonable change overall and the structure is sound.
Still going through the files one by one to check for edge cases before writing up findings.
[Tool use interrupted])
FAIL: Test 4: unexpected fallthrough journal line on a first-arm pass -- [leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=writes_csv_empty
[leadv2-dispatch-product-close] product_close task=t4sig004 worker_liveness=unknown author=codex handle=- action=proceed_legacy
[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=t4sig004 reason=empty_scope_writes_csv
[leadv2-dispatch-product-close] selfcheck task=t4sig004 status=degraded checks=0 skipped=2
[leadv2-dispatch-product-close] e2e_gate task=t4sig004 status=disabled reason=kill_switch
[leadv2-dispatch-product-close] review_routing_yaml task=t4sig004 source=plugin
[leadv2-dispatch-product-close] review_signals task=t4sig004 protected_path=1 source=no_lane_writes_failclosed matched=-
[leadv2-dispatch-product-close] route_resolved by=arbiter role=reviewer arm=glm task=t4sig004 reason=cheapest_capable util_glm=unknown_capped util_codex=unknown_capped util_claude=unknown_capped util_freepool=0 reset_glm=n/a reset_codex=n/a reset_claude=n/a reset_freepool=n/a headroom_w=1 headroom_unknown=probe claude_account_state=unknown claude_probe_penalty=50 claude_priced_from=unknown_probe_penalty arm_excluded=codex:price_ratio,fable:price_ratio,opus:not_in_pool,sonnet:price_ratio arb_rev=13cff1513f08 matrix_rev=a7adb07b0b4e floor_mode=bulk_only floor_mode_source=yaml test_only=0 complexity=unknown duration_class=unknown complexity_policy=capability_fit remaining=unknown reset_in=n/a reset_basis=n/a probe_outage=glm,codex,claude failure_memory=absent_key complexity_source=unknown conf=0.0 req_eff=3.0 fit_mode=on fit_pick=glm fit_differs=0 fit_bucket=glm:0,codex:0,codex:0,sonnet:0,fable:0
[leadv2-dispatch-product-close] review_pool_resolve task=t4sig004 rc=0 reviewer=glm pool_n=2
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=arm_no_verdict arm=glm reason=no_verdict_marker tried=glm remaining=0
[leadv2-dispatch-product-close] review_gate task=t4sig004 status=blocked reason=no_verdict_marker tried=glm body=docs/handoff/dispatch-t4sig004-review/review-glm.md bytes=212
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh (scope-selected ad-hoc)

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-review-silence-gate.sh (scope-selected ad-hoc)
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: bash -n clean (lib/leadv2-refusal-classify.sh)
[TEST] PASS: Test 1 (empty_output): exit 6
[TEST] PASS: Test 1 (empty_output): review-gate.md status=blocked reason=no_verdict_marker (pool exhausted)
[TEST] PASS: Test 2 (thin_output): exit 6
[TEST] PASS: Test 2 (thin_output): review-gate.md status=blocked reason=no_verdict_marker (floor rejects a 1-line unrelated file, pool exhausted)
[TEST] PASS: Test 3 (peak_hours_refusal_with_fallback): exit 0
[TEST] PASS: Test 3: review-gate.md status=pass after glm refused and sonnet fell back
[TEST] PASS: Test 3: journal/decision line carries arm_refused arm=glm reason=refused_peak_hours
[TEST] PASS: Test 4 (peak_hours_refusal_no_fallback): exit 9
[TEST] PASS: Test 4: review-gate.md status=unreviewed reason=all_arms_unavailable tried=glm,sonnet
[TEST] PASS: Test 5 (normal_review_still_passes): exit 0
[TEST] PASS: Test 5: review-gate.md status=pass -- silence-loudness fix does not trade for a false red
[TEST] PASS: Test 6 (crash_backstop): non-zero exit (rc=143) on SIGTERM mid-review
[TEST] PASS: Test 6: review-gate.md exists with reason=review_crashed -- the EXIT-trap backstop fired (D3)

[TEST] 15 passed, 0 failed

[CORE-OFFLINE] plugins/leadv2/scripts/tests/test-silent-arm-index-and-cross-repo.sh (scope-selected ad-hoc)
[TEST] PASS: Case 1: report staged in the lane's index (docs/handoff, never committed) is NOT classified arm_produced_nothing
[TEST] PASS: Case 2: a commit naming FOUNDER_TASK_ID in the sibling leadv2 repo is NOT classified arm_produced_nothing
[TEST] PASS: Case 3: an unrelated commit in the sibling repo does not suppress a genuinely silent verdict
[TEST] PASS: Case 4: a genuinely silent arm (no index content, no cross-repo evidence) is still classified arm_produced_nothing
[TEST] PASS: MUTATION CONTROL: reverting both escape hatches makes Case 1 and Case 2 go red (arm_produced_nothing again)
ALL PASS: test-silent-arm-index-and-cross-repo.sh (5 passed)

[CORE-OFFLINE] plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh (scope-selected ad-hoc)
PASS fable_exited terminal value: no_work
PASS fable_exited cause: empty_diff
PASS fable_exited close rc: 5
PASS fable_exited exited promptly (1s): prompt
PASS fable_late terminal value: landed
PASS fable_late late bytes reached review: reviewed
PASS fable_late close rc: 0
PASS fable_heartbeat_only terminal value: landed
PASS fable_heartbeat_only late bytes reached review: reviewed
PASS fable_heartbeat_only close rc: 0
PASS fable_stale_heartbeat terminal value: no_work
PASS fable_stale_heartbeat cause: empty_diff
PASS fable_stale_heartbeat close rc: 5
PASS fable_stale_heartbeat exited promptly (1s): prompt
PASS fable_finalizer terminal value: landed
PASS fable_finalizer late bytes reached review: reviewed
PASS fable_finalizer close rc: 0
PASS sonnet_raw_handle terminal value: landed
PASS sonnet_raw_handle late bytes reached review: reviewed
PASS sonnet_raw_handle close rc: 0
PASS haiku_exited terminal value: no_work
PASS haiku_exited cause: empty_diff
PASS haiku_exited close rc: 5
PASS haiku_exited exited promptly (1s): prompt
PASS opus_exited terminal value: no_work
PASS opus_exited cause: empty_diff
PASS opus_exited close rc: 5
PASS opus_exited exited promptly (1s): prompt
PASS sonnet_numeric_compat terminal value: no_work
PASS sonnet_numeric_compat cause: empty_diff
PASS sonnet_numeric_compat close rc: 5
PASS sonnet_numeric_compat exited promptly (1s): prompt
RESULT pass=32 fail=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=7 fail=4 missing=0
```
