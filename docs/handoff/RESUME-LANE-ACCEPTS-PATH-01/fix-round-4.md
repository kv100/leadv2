# RESUME-LANE-ACCEPTS-PATH-01 — fix round 4

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RESUME-LANE-ACCEPTS-PATH-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh,docs/handoff/RESUME-LANE-ACCEPTS-PATH-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `f0160b9`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Review verdict on round 3 (reviewer glm, `review-glm.md`)
status=fail high=1:
- **[High] `leadv2-dispatch-code.sh:353`** — `_lv2_is_lane_worktree_path` matches only
  `basename(cand) == <id>` against the ids in `git worktree list --porcelain`, never `cand == wt`
  (the worktree's absolute path). So an in-repo subdirectory whose basename collides with a lane id
  (e.g. `<root>/docs/handoff/RESUME-LANE-ACCEPTS-PATH-01`) is accepted as the lane worktree.

## Do
1. Compare the CANONICALISED candidate (`cd cand && pwd -P`) for equality with the canonicalised
   `worktree <path>` line of `git worktree list --porcelain`; basename is not an identity. Keep the
   branch check (`branch refs/heads/worktree-<id>`) and the main-checkout refusal.
2. Add the collision case to `test-resume-lane-arg-shapes.sh`: `--resume-lane <root>/docs/handoff/<id>`
   (create that dir in the fixture) → refused with the shape-naming message; and the real linked
   worktree path → accepted.
3. Mutation negative control, RUN and paste red: replace the path equality with the basename compare
   again → the collision case red. Revert.
4. Append "## Round 4 evidence" (suite time, green, control red) to report.md; commit.
