# WORKERS-MUST-COMMIT-01 — fix round 2

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKERS-MUST-COMMIT-01`
LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh,plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/kimi-coder.sh,plugins/leadv2/scripts/freepool-coder.sh,plugins/leadv2/scripts/claude-subsession.sh,plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh,tests/run-all.sh,docs/handoff/WORKERS-MUST-COMMIT-01/
Continue from the existing commits on this branch (`git log main..HEAD`, last `0a0d2f1`); run with
`LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST (`git merge main`, resolve if needed) so the land
is ff-able — three lanes tonight passed review and then could not land.

## Review verdict on round 1 (reviewer glm) — status=fail high=2
- **[High] `lib/leadv2-worker-epilogue.sh:92`** — `git status --porcelain` collapses an untracked
  DIRECTORY to one line (`?? plugins/leadv2/hooks/lib/`), so a new in-scope directory of work is
  matched against LANE_WRITES as a directory path, classified foreign, and left uncommitted — the
  exact defect this task exists to remove (BEAT-LOOP-ORPHANS-01 R1 lost `hooks/lib/` this way).
  Use `git status --porcelain --untracked-files=all` (or `git ls-files --others --exclude-standard`)
  so every file is classified individually.
- **[High] `glm-coder.sh:1731`** — the epilogue is wired into glm-coder only; `kimi-coder.sh:1577`
  and `freepool-coder.sh:1820` have the same finalize → `leadv2-lane-outcome.sh` shape with no
  epilogue call, and `claude-subsession.sh` (the sonnet/opus arm — the arm that left PROMISE and
  GLM-ARM uncommitted tonight) is not covered either. The invariant must hold on EVERY arm.

## Do
1. Fix the porcelain collapse; add suite case (e): new untracked directory inside LANE_WRITES →
   every file under it committed; and (f): new directory outside → listed per file in
   `foreign_dirty`, nothing committed.
2. Wire the epilogue into kimi-coder, freepool-coder and claude-subsession at the same
   finalize point; add a grep-gate case to the suite: all four launchers call the epilogue
   (zero launchers without it). If a launcher has no lane worktree (e.g. the `--protected` mode
   writes elsewhere), the epilogue must detect that and exit 0 with `worker_exit=no_lane`.
3. Mutation negative controls, RUN and paste red: (a) revert to plain `--porcelain` → case (e) red;
   (b) remove the epilogue call from one launcher → grep-gate red. Revert both.
4. `bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh`
   → paste the FALSIFIABLE line.
5. "## Round 2 evidence" in report.md; commit. An uncommitted exit is a failed round.
