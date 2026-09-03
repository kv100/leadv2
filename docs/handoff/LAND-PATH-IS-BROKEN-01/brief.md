# LAND-PATH-IS-BROKEN-01 — deploy-merge cannot land a real lane; make landing a merge, not a rebase

LANE_WRITES: plugins/leadv2/scripts/leadv2-deploy-merge.sh,plugins/leadv2/scripts/lib/leadv2-land.sh,plugins/leadv2/scripts/leadv2-worker-epilogue.sh,plugins/leadv2/scripts/tests/test-land-path.sh,tests/run-all.sh,docs/handoff/LAND-PATH-IS-BROKEN-01/
Run suites with `LEADV2_SUITE_LOCK_DISABLE=1`. Merge main FIRST. Never commit `docs/leadv2/`,
`docs/LEAD_V2_STATE.md`, `docs/handoff/dispatch-nw*`. Commit by LANE_WRITES pathspecs; an uncommitted exit
is a failed round. Review-facing text in ENGLISH.

## Measured (lead, 2026-09-02 — 9 lands tonight, 0 through the script)
`leadv2-deploy-merge.sh` failed on every lane it was given and the lead landed each by hand (10–20
min each). Three distinct causes, all reproduced:
1. **Dirty tracked files in the lane** (`docs/handoff/dispatch-nw*/phases.d/*.yaml`, `docs/LEAD_V2_STATE.md`,
   `docs/leadv2/*` symlinks retargeted to /tmp) — the suites/hooks dirty them while the worker runs.
   Script prints `cannot rebase: unstaged changes`, then prints OK with rc=1, main untouched.
2. **Rebase of a branch that contains merge commits** (every lane merges main before review, as the
   briefs now require) onto origin/main → conflicts on every merged hunk. Rebase is the wrong operation
   for a lane that already merged main; the right one is `git merge --ff-only` (lane contains main) or a
   plain merge commit.
3. **Main checkout holds ignored copies of files a lane tracks** (`.compact-freeze.md`, handoff
   fixtures) → `merge` refuses: "untracked working tree files would be overwritten".
Also: the script always ends `BLOCK: .claude/leadv2-overrides/deploy.sh not found` rc=1 even when
main was merged (LEADV2-HOOK-CACHE-DEPLOY-01 added the deploy.sh; verify it is now found).
Workaround the lead used every time: a fresh worktree on the lane tip (`git worktree add … -b
worktree-<ID>-LAND <lane-branch>`), `git checkout -- <dirty>`, `git rm --cached <state files>`, then
`git merge --ff-only` in main and a separate push.

## Do
1. Replace the rebase step: if the lane already contains `origin/main` → `--ff-only`; if it does not →
   `git merge origin/main` INSIDE the lane (a merge commit, never a rebase of merge commits) → then
   `--ff-only` into main. Rebase only when the lane has zero merge commits (`git rev-list --merges
   main..lane` empty) AND the founder flag `LEADV2_LAND_REBASE=1` is set; otherwise never.
2. Pre-land hygiene, automatic and journaled: in the lane, `git checkout -- docs/leadv2
   docs/LEAD_V2_STATE.md docs/handoff/dispatch-nw*` (paths from ONE list in `lib/leadv2-land.sh`, shared
   with the worker epilogue so the auto-commit never captures them either); `git rm --cached` any
   tracked file that is ignored on main (derive the list, do not hand-code `.compact-freeze.md`);
   refuse with a named reason if anything else is dirty.
3. Land from a throwaway worktree on the lane tip (the lead's workaround, made the code path), never
   from the lane's own worktree (its hooks and suites keep dirtying it) and never by touching the
   main checkout's working tree beyond the ff.
4. Exit code truth: rc=0 only when `git rev-parse main` moved to the lane tip AND the push succeeded;
   the deploy.sh BLOCK is a separate, later step with its own line — never rc=1 after a successful
   land, never OK before one.
5. Suite `test-land-path.sh` on a scratch repo (never the shared tree): (a) lane with merge commits
   lands ff; (b) lane behind main lands via merge commit then ff; (c) dirty tracked state files are
   restored and the land proceeds, with the journal line; (d) tracked-but-ignored-on-main file is
   dropped from the lane before the ff; (e) rc=1 with a named reason when a NON-state file is dirty.
   Mutation negative controls, RUN and paste red: restore the rebase step → (a) red; drop the hygiene
   list → (c) red. Revert. Register in `tests/run-all.sh` (`leadv2-deploy-merge` stem);
   `--scope changed` line + FALSIFIABLE pasted.
6. Live proof on the merged tree: land ONE real finished lane through the script (the lead names it in
   the fix-round if none is ready) and paste the journal lines from preflight to push.

## Do NOT
- Never `reset --hard`, `clean`, `stash` or `push --force` anywhere on the shared tree (deny-floor).
- Do not delete lane worktrees or branches in this lane.
