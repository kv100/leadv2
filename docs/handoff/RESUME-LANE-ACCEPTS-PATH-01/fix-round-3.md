# RESUME-LANE-ACCEPTS-PATH-01 — fix round 3

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/RESUME-LANE-ACCEPTS-PATH-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-resume-lane-arg-shapes.sh,docs/handoff/RESUME-LANE-ACCEPTS-PATH-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `26267b4`); run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Review verdict on round 2 (reviewer glm; full text in `docs/handoff/RESUME-LANE-ACCEPTS-PATH-01/review-glm.md`)
status=fail critical=0 high=2. Read `review-glm.md` in full first.

- **[High] `leadv2-dispatch-code.sh:397`** — hunk 2 deletes the cwd-root fallback and the
  `_LV2_FOREIGN_ROOT_*` assignments, but the WARN text still says "using cwd-derived root" and the
  `project_root_guard foreign_env_overridden` path still references state that no longer exists. Either
  the fallback stays and is tested, or it goes and every message / journal line / reader of
  `_LV2_FOREIGN_ROOT_*` goes with it. No half-deleted mechanism.
- **[High] `leadv2-dispatch-code.sh:855`** — the absolute-path branch of `--resume-lane` validates only
  "git-common-dir parent == project root", so it accepts PROJECT_ROOT itself and ANY in-repo
  subdirectory as a "lane worktree". Accept only a path that `git worktree list --porcelain` names as a
  linked worktree of PROJECT_ROOT (never the main checkout), whose branch is `worktree-<id>`, and whose
  basename equals the task id. Refuse everything else with the shape-naming message.

## Do
1. Fix both. Add cases to `test-resume-lane-arg-shapes.sh`: (a) `--resume-lane <PROJECT_ROOT>` refused;
   (b) `--resume-lane <PROJECT_ROOT>/plugins` refused; (c) a real linked worktree path accepted; (d) the
   foreign-root WARN/journal text matches the code that remains (grep-gate on the dead names).
   The suite currently takes 71 s and the review gate's falsifiability probe times out at 60 s —
   bring it under 40 s (share one fixture repo across cases instead of building one per case).
2. Mutation negative control, RUN and paste red: relax the worktree check back to "common-dir parent
   == root" → (a) and (b) red.
3. Append "## Round 3 evidence" to report.md (suite time, green run, control red); commit.
