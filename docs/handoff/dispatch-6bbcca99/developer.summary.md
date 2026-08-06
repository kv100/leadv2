verdict: APPROVE
next_action: review_round_2

Fixed the close gate discarding lane work when CROSS_REPO_DIFF was off.

- `pc_scope_diff()` now resolves the lane worktree unconditionally; `CROSS_REPO_DIFF` only picks multi-repo grouping.
- Added `_pc_lane_dirty` — empty diff + dirty lane → `refused/unscoped_lane_work` instead of `no_work`.
- New suite `test-lane-diff-single-repo.sh` (4 cases, C1/C2 red pre-fix), registered in `run-core-offline.sh`.

Full: full.md
