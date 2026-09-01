# GLM-ARM-THROUGHPUT-01 — one per-repo GLM lock serialises every lane; glm-flash never launches

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GLM-ARM-THROUGHPUT-01`
LANE_WRITES: plugins/leadv2/scripts/glm-coder.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-glm-lock-per-lane.sh,plugins/leadv2/scripts/tests/test-glm-flash-handle.sh,tests/run-all.sh,docs/handoff/GLM-ARM-THROUGHPUT-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Evidence (2026-09-01, four lanes in ~/Projects/leadv2)
1. `glm-coder.sh:450` — `lock_dir_for "${repo_hash}"`: ONE lock per repository. With four lanes
   in the same repo, every second GLM dispatch printed
   `arm_refused by=router model=glm reason=glm_refused_lock_busy` and spilled to Sonnet:
   3 of 4 dispatches tonight (RESUME-LANE R4, ONE-LANE R4, BEAT-LOOP R2). GLM is the founder's
   PRIMARY code writer (GLM-FIRST-01) at ~1% quota use; the lock turns it into a one-lane arm and
   burns Claude quota instead. The lock exists to stop two GLM runs writing the same worktree —
   that invariant is per LANE WORKTREE, not per repo.
2. `leadv2-dispatch-code.sh:5025` — every `glm-flash` spawn ends
   `spawn(glm-flash) handle= ... has no live run record -- treating as launch failure`: the flash
   launcher returns an EMPTY handle, so glm-flash has never launched a worker through the router
   tonight; each attempt costs a launcher round trip and a fallback.

## Do
1. Key the lock on the resolved lane worktree (`repo_hash` + worktree path hash; keep a
   repo-wide lock ONLY for the main checkout, where two writers really would collide). Two runs in
   two worktrees of one repo must both acquire; two runs in the same worktree must not. Keep the
   existing "no started marker → refuse" rule and the rc-75 `LEADV2_DISPATCH_REFUSED: lock_busy`
   contract intact.
2. Find why the flash path returns an empty handle: trace `bg` → run-dir creation → handle echo
   for `--model glm-5.3-flash` (GLM-53-FLASH-ARM-01 made it share the launcher — check the branch
   that prints the handle is reached for the flash model id and that `status <handle>` resolves
   the same RUNS_DIR). Fix so `bash glm-coder.sh status <handle>` is true right after `bg`.
3. Suites (hermetic, `LEADV2_GLM_LOCK_ROOT` / `RUNS_DIR` pointed at temp dirs, a fake `claude`
   on PATH that sleeps): `test-glm-lock-per-lane.sh` — (a) two `bg` calls in two worktrees of one
   fixture repo both acquire; (b) two in the same worktree → second is rc 75 + marker; (c) main
   checkout keeps the repo lock. `test-glm-flash-handle.sh` — `bg --model glm-5.3-flash` prints a
   non-empty handle and `status` on it is true. Each under 20 s. `EXTRA_SUITE_MAP` rows; prove
   with `--scope changed`.
4. Mutation negative controls, RUN and paste red: (a) revert the lock key to repo-only → case (a)
   red; (b) re-break the flash handle echo → flash suite red. Revert both.
5. `report.md`; commit in the lane. An uncommitted exit is a failed round.
