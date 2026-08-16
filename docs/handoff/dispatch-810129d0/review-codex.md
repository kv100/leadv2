# Codex Adversarial Review

Target: branch diff against HEAD
Verdict: needs-attention

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=3 medium=0 low=0
No ship: lane isolation, Gate-1 retry handling, and commit targeting are unsafe.

Findings:
- [high] Fallback destroys required lane isolation (plugins/leadv2/scripts/leadv2-fork-session.sh:99-103)
  Because `ensure` returns the main checkout on any worktree failure and this only checks that the returned directory exists, preflight can hand a fork the shared checkout and let concurrent edits collide.
  Recommendation: Reject a returned lane root unless it is the expected registered worktree path, including when lane isolation is disabled.
- [high] Gate-1 retries discard the pending question (plugins/leadv2/scripts/leadv2-fork-session.sh:160)
  Every retry after exit 3 invokes `leadv2-ask.sh` again to generate a new QID, so an answer to an earlier visible question is never polled and the fork can remain blocked while accumulating duplicate prompts.
  Recommendation: Persist the initial QID per task and have retries poll that record instead of creating another question.
- [high] Fork commits can target the lead checkout (plugins/leadv2/prompts/fork-session-mission.md:35)
  The mission forbids changing CWD but merely says to commit inside the lane, so ordinary Git commands use the shared lead CWD and can commit outside the task branch before merge gates run.
  Recommendation: Require `git -C "$LANE_ROOT"` for every Git operation or provide a lane-scoped commit wrapper.

Next steps:
- Block the change until the three high-severity paths are fixed and covered by failure/retry tests.
