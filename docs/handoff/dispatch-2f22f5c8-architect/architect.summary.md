verdict: APPROVE
next_action: continue

Design: preflight refuses instead of degrading; Gate-1 QID persisted across retries; H3 holds and gets a lane-scoped commit wrapper.

- H1: `assert_isolated_lane` (expected path + `worktree list` + branch) before register; `LEADV2_LANE_WORKTREE=off` fatal for forks only.
- H2: `<control-plane>/fork-ask/<task>.yaml` (qid+fingerprint); retry polls, never re-asks; exit 3 = gate not passed.
- H3: `commit` op via `git -C "$LANE_ROOT"`; ownership narrowed — Phase 6 split.

Full: architect.full.md
