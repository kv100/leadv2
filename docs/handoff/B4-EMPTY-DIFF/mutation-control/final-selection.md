# B4 final merge-base selection proof

The checkpoint was absent, then written with the merge base before this selection-only run and removed by its EXIT trap. This rechecks selection after the report commit; it does not claim another broad test execution.

```text
base=fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982
HEAD=9b0afc20a5abab55153d488d92de19f92311a4f5
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
```
