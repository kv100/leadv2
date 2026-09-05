# LANE-STATE-LEAK-01 — session-global state is written into every lane worktree

## What happened

The founder opened Source Control and saw **226 changes across ~30 worktrees**. Almost none of it
was work. Each of ~30 lane worktrees permanently showed the same 5–13 modified files that no lane
had ever touched, so no lane could be clean, and the `unscoped_lane_work` scope gate has been
firing on exactly this class of file — it killed lane `7ceeda42` in persona-engine today, with
`offending=docs/tasks.yaml`.

persona-engine has gitignored and untracked the set as a stopgap (`ffb0c8c0a`). **That hides the
symptom and does not fix it:** the writes still land in whichever worktree happens to be current,
so the state is fragmented across worktrees instead of being one thing, and a lane that is removed
takes its slice of that state with it.

## The mechanism, already located — do not re-derive it

`plugins/leadv2/scripts/leadv2-state-path.sh` exists for precisely this problem. Its header says:

> ALL scripts/hooks that touch active.yaml / bus.jsonl / merge-queue.jsonl / .merge.lock /
> open-threads.md MUST resolve the path through this script — no hardcoded `docs/leadv2/...`
> string for these five files anywhere else.

It resolves one canonical root outside any worktree via `git rev-parse --git-common-dir`, which is
identical from every worktree of the same repo.

**The bug is that the managed set was never extended past those five.** Seven more pieces of
session-global state use a raw `$PROJECT_ROOT/docs/leadv2/...` path, and `PROJECT_ROOT` is the
CALLING WORKTREE:

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- `:876` `_leadv2_glm_deferred_path` → `$PROJECT_ROOT/docs/leadv2/glm-deferred.jsonl`
- `:877` `_leadv2_arm_exceptions_path` → `$PROJECT_ROOT/docs/leadv2/.arm-exceptions-<date>`
- `:879` `_leadv2_glm_deferred_mission_path` → `$PROJECT_ROOT/docs/leadv2/glm-deferred.d/<id>.md`

`plugins/leadv2/scripts/leadv2-broad-status.sh`
- `:36` `FOUNDER_STATUS_PATH` → `$PROJECT_ROOT/docs/leadv2/founder-status.md`
- `:44` `FOUNDER_STATUS_FULL_PATH` → `.../founder-status-full.md`
- `:61` `EMPTY_SINCE_PATH` → `.../.board-empty-since`
- `:62` `FOUNDER_STATUS_EPOCH_PATH` → `.../.founder-status-epoch`

Each of these is per-SESSION or per-REPO state, never per-lane. A deferral ladder, an
arm-exception date file, a status render and its epoch are single-valued facts about the whole
board; there is no meaning to a lane having its own copy.

## What to build

Route all seven through `leadv2-state-path.sh` and extend its managed set (and its header comment,
which is the contract) to name them. Preserve the existing `LEADV2_*_PATH` env overrides — the
offline tests use them.

Two things to get right:

1. **Migration, not just redirection.** A worktree today holds real content at these paths — the
   deferral ladder in particular. `leadv2-state-path.sh` already documents a migration behaviour
   ("if docs/leadv2/<name> exists in THIS worktree, its content is MOVED into the control plane").
   Follow the same shape so an upgrade does not silently start from an empty ladder, and so
   `glm-deferred.d/` merges rather than clobbers.
2. **`founder-status.md` is read by the pulse relay and by the founder.** Keep a readable path in
   the main checkout — the symlink shape the resolver already uses is fine — so
   `docs/leadv2/founder-status-full.md` in the message text stays a path a human can open.

## Done means

1. `grep -rn 'PROJECT_ROOT/docs/leadv2/' plugins/leadv2/scripts/` returns nothing for these seven.
   Paste the output.
2. A test proving the invariant: resolve each of the seven from a linked worktree and from the
   main checkout and assert the two paths are identical. This is the whole point; if it is not
   asserted it will regress.
3. A migration test: pre-existing content at the old worktree path is present at the new canonical
   path afterwards, and `glm-deferred.d/` entries from two different worktrees both survive.
4. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` green, plus the four existing suites
   that touch these files (`test-glm-deferred-ladder.sh`, `test-broad-status-lanes-blind.sh`,
   `test-broad-status-renderer-truth.sh`, `test-pulse-empty-board.sh`).
5. `git diff --stat`.

## Scope

`plugins/leadv2/scripts/leadv2-state-path.sh`
`plugins/leadv2/scripts/leadv2-dispatch-code.sh` — the three path helpers only
`plugins/leadv2/scripts/leadv2-broad-status.sh` — the four path variables only
`plugins/leadv2/scripts/tests/`

This is the plugin repo, the single source for persona-engine, m3-market and respiro-ios. Change
these files once, here. Do not add a per-repo copy anywhere, and do not touch a consuming repo.

## Not in scope

The SCRIPT-SIZE-AUDIT work (`docs/handoff/SCRIPT-SIZE-AUDIT-20260821/`) — the founder may open a
separate session on it. Do not start it, and do not restructure either dispatcher beyond the path
helpers named above.
