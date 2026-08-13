verdict: APPROVE
next_action: continue

Design ready: hoist lane-worktree resolution out of the `CROSS_REPO_DIFF` guard, and block an empty diff over a dirty lane as `refused`/`unscoped_lane_work` instead of `no_work`.

- E1 `:861-868` unconditional lane root; flag keeps only multi-repo grouping.
- E2 `:1034-1039` `_pc_lane_dirty` branch; `partial_diff`/`asked_into_void` untouched.
- New 4-case red-first suite + `run-core-offline.sh` registration.

Full: architect.full.md
