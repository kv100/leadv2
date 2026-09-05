# Lead evidence — this lane is currently running INSIDE the bug it exists to fix

Captured live 2026-09-06T~01:35 local. This is a fourth root authority, beyond the two
splits already documented in `brief.md` and `lead-addendum-line-drift.md`. It is the
cleanest reproduction of the defect we have.

## What happened

The lead dispatched this line from `~/Projects/leadv2` with **both** root variables pinned:

```
LEADV2_PROJECT_ROOT=$HOME/Projects/leadv2 PROJECT_ROOT=$HOME/Projects/leadv2 \
  leadv2-dispatch-code.sh --task-id PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01 ...
```

The **phase store obeyed** — `~/Projects/leadv2/docs/handoff/dispatch-063a910e/phases.d/`
holds `classify.yaml`, `plan.yaml`, `gate1.yaml`, `build.yaml`, and
`~/Projects/persona-engine/docs/handoff/dispatch-063a910e/` does not exist at all.

The **active-lane registry did not.** A live worker for this same task id is registered in
`~/Projects/persona-engine/docs/leadv2/active.yaml` (row `session_id:
s-20260905T223242Z-1-74904`, `started_at: 2026-09-05T22:32:42Z`, `phase: build`,
`class: Light`, `writes: null`, `writes_reason: prepass_pending`, preceded by a
`recovered_unowned_no_pid` lane event) with:

```
worktree: /Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01
```

## Why that worker cannot succeed

The worker is alive — GLM run `260906-013255-PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01-16c6`,
pids 2557 / 2781 / 2785 / 2944. Its mission opens with a hard pin:

> WORKTREE PIN: all edits go in
> `/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01`;
> do NOT cd to the main checkout even if the mission text names it.

And in that worktree:

```
$ ls .../worktrees/PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01/plugins/leadv2/scripts/leadv2-phase-record.sh
ls: ... No such file or directory
```

It is a persona-engine checkout (`agent/`, `contracts/`, `engine/`, `docs/`), on branch
`worktree-PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01` at `9f9bcaf2f "lane ... anchor"`. **The
one file this line must edit is not there, and the pin forbids going where it is.** The lane
whose job is "records land in the wrong repo" is itself pinned to the wrong repo.

## What this adds to the brief

`brief.md` locates the defect in `leadv2-phase-record.sh`'s own root resolution and
prescribes an existence gate in `cmd_record`. That remains right, but it is **not
sufficient**: the phase store honoured the pinned root here and the lane still landed in the
wrong repository, because **the worktree/registry path is resolved by a different authority
that the two env vars do not reach.**

So the count of independent root authorities is now four:

1. `leadv2-phase-record.sh` — `LEADV2_PROJECT_ROOT` > `PROJECT_ROOT` > git-toplevel > `pwd`
2. `leadv2-journal.sh:14` — `CLAUDE_PROJECT_ROOT` > `CLAUDE_PROJECT_DIR` > git-toplevel > `pwd`
3. `leadv2-event.sh:17` — `LEADV2_EVENT_LOG_DIR`, defaulting to live `~/.claude/cache/...`
4. **the active-lane registry / worktree pin** — obeyed neither pinned variable here

Part (b) of the brief ("decide what the root IS, and make it one source") must account for
authority 4, or the fix will pass its own tests and still put lanes in the wrong repository.

## Not done, deliberately

That worker belongs to another session and was **not** killed, and its worktree was **not**
pruned — pruning worktrees under live lanes has cost us two lanes before. It is recorded
here and surfaced to the founder and to the peer session instead. Whoever owns it should
decide: it is burning GLM at `effort=max` on a file that is not in its tree.
