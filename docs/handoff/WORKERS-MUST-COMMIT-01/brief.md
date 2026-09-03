# WORKERS-MUST-COMMIT-01 — an uncommitted exit is a failed round, and the dispatcher must say so

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/WORKERS-MUST-COMMIT-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh,plugins/leadv2/scripts/tests/test-worker-commit-epilogue.sh,tests/run-all.sh,docs/handoff/WORKERS-MUST-COMMIT-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Evidence (2026-09-01, one session)
Five lanes reported `LEADV2_LANE_OUTCOME outcome=completed ... work=yes` and left their work
UNCOMMITTED in the lane worktree: PROMISE-GUARD-TURN-IT-ON-01 (twice), PLUGIN-PAPERCUTS-01 (twice),
BRAIN-CLASS-LIVE-01, FABLE-THINK-TIER-01 (24 files). Each time the lead had to
`git add -A && git commit -m "salvage(...)"` by hand before review could start. The dispatcher's own
comment (leadv2-dispatch-code.sh:195, :6896) already calls an uncommitted exit "produced NOTHING",
but nothing enforces it: the outcome line is written from the worker's prose, not from `git status`.

## Do
1. Worker epilogue (runs after the model exits, inside `glm-coder.sh __run_child` / the claude
   sub-session wrapper, i.e. for EVERY arm): in the lane worktree, if `git status --porcelain`
   shows tracked or untracked changes under LANE_WRITES, auto-commit them as
   `"<task-id> round <n>: auto-commit (worker exited dirty)"` and write
   `worker_exit=dirty auto_committed=<n files>` into meta.yaml + progress.log. Files outside
   LANE_WRITES are NOT committed — list them in progress.log as `foreign_dirty=` and leave them.
2. `LEADV2_LANE_OUTCOME` is computed, not quoted: `work=yes` requires `git log <anchor>..HEAD`
   to be non-empty after the epilogue; otherwise `outcome=no_work` regardless of what the model said.
   Journal one line `worker_claim=completed evidence=no_commit` when the two disagree.
3. Suite `test-worker-commit-epilogue.sh` (hermetic fixture repo + fake worker that edits a file
   and exits): (a) dirty in-scope exit → auto-commit exists, outcome work=yes; (b) dirty
   out-of-scope exit → no commit, `foreign_dirty` listed, outcome no_work; (c) clean committed exit →
   untouched. Under 20 s. `EXTRA_SUITE_MAP` row so a change to the epilogue selects it; prove with
   `--scope changed`.
4. Mutation negative control, RUN and paste red: make the epilogue skip the commit → (a) red. Revert.
5. `report.md` with the evidence lines. Commit in the lane.
