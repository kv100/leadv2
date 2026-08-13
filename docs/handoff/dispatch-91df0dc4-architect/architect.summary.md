verdict: APPROVE
next_action: continue

Resolve the lane worktree unconditionally; `CROSS_REPO_DIFF` keeps only its repo-split job.

- Empty diff + dirty lane root (only when a real lane worktree was used) → `refused`/`unscoped_lane_work`, never `no_work`.
- Clean lane still `no_work`/`empty_diff`; `partial_diff`/`asked_into_void` untouched.
- New 6-case red-first suite + run-core-offline registration.

Full: architect.full.md
