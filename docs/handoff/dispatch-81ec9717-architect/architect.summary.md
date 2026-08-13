verdict: APPROVE
next_action: continue

# architect — GATE-LANE-DIFF-ONLY-WHEN-CROSS-REPO-01

Split `LEADV2_REVIEW_DIFF_CROSS_REPO` into fan-out vs lane-root; resolve the lane worktree always; a dirty lane blocks as `refused/lane_diff_unscoped`, not `no_work`.

- Blocker: two shipped suites (lane-writes C3, landing-diff Q3-pair) assert the defect — respec onto new `LEADV2_REVIEW_DIFF_LANE_ROOT`, do not delete.
- Dirty check must exclude `docs/handoff|docs/leadv2` or "did nothing" becomes a block.

Full: architect.full.md
