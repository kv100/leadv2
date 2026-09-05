# LANE-STATE-LEAK-01, the durable half — stop this class from coming back

Round 1 routes seven paths through `leadv2-state-path.sh`. That fixes today. It does not stop the
next file from being added the same way, which is the founder's actual complaint: **this problem
keeps recurring.**

## Why it recurs — measured, not theorised

The knowledge existed and did not propagate. As of 2026-08-23:

| repo | ignore rules for the runtime-state set | task-state files still TRACKED |
|---|---:|---:|
| `~/Projects/leadv2` (plugin) | present since some earlier fix | 291 |
| `persona-engine` | added today, by hand | 43 → 0 today, by hand |
| `respiro-ios` | **0** | — |

Three consuming repos, three different states, one shared plugin. Every fix so far has been a
per-repo `.gitignore` edit made by whoever noticed, so a repo nobody noticed stays broken.

And the per-repo rule is weaker than it looks: persona-engine has had `docs/leadv2/tasks/` in
`.gitignore` since long before today, yet 43 files under it were tracked and mutating in every
worktree — **gitignore does not apply to already-tracked files**. The rule read as done while doing
nothing. That is three instances of the identical failure in one day.

## What to build

### 1. Write runtime state OUTSIDE the repo, not to a canonical path inside it

`leadv2-state-path.sh` already computes `~/.claude/leadv2-state/<repo-slug>/` from
`git rev-parse --git-common-dir`. Round 1 keeps a `docs/leadv2/<name>` symlink into it. For the
files a human never opens — `glm-deferred.jsonl`, `glm-deferred.d/`, `.arm-exceptions-*`,
`.founder-status-epoch`, `.board-empty-since`, and the `docs/leadv2/tasks/` task-state tree — drop
the in-repo symlink entirely and keep only the out-of-repo path.

A file that does not exist inside any working tree cannot be tracked, cannot dirty a worktree,
cannot trip the `unscoped_lane_work` gate, and needs no `.gitignore` line in any consuming repo —
including one that does not exist yet. That is the property we want; a canonical path inside the
repo does not have it.

Keep an in-repo readable path only where a human actually opens the file: `founder-status.md` and
`founder-status-full.md` are cited by path in the status message itself. `open-threads.md` is
authored and reviewed by hand and stays a tracked document — it is not in this set.

### 2. A guard that fails when plugin-written state resolves inside a working tree

Add it to the plugin's own offline suite so it runs on every change — not as a repo-side hook each
consuming repo would have to install separately, which is the propagation failure again.

Assert, for every path the plugin writes: the resolved absolute path is not under any
`git rev-parse --show-toplevel` of a consuming repo. A new file added the old way turns the suite
red the same day, in the repo that owns the mistake.

### 3. One-shot propagation for what is already tracked

The guard prevents new instances; it does not clean existing ones. Ship a small idempotent command
— `leadv2-state-migrate` or similar — that a consuming repo runs once: untracks the set with
`git rm --cached`, moves any content to the out-of-repo root, and reports what it moved. Then run
it for `respiro-ios` (0 rules today) and for the plugin repo's own 291 tracked task files.

Do not hand-edit three `.gitignore` files and call it done. That is the loop we are trying to
leave.

## Done means

1. For each path in the set, its resolved location is outside every consuming repo's working tree.
   Paste the resolved paths.
2. The guard, red against a deliberately reintroduced in-repo write, then green. Say that you
   verified it by breaking it on purpose.
3. The migration command, run against `respiro-ios` and the plugin repo, with its report pasted —
   `git status --porcelain` in both afterwards should list no file from the set.
4. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` green.
5. `git diff --stat`.

## Scope

`plugins/leadv2/scripts/leadv2-state-path.sh`
`plugins/leadv2/scripts/tests/`
a new migration script under `plugins/leadv2/scripts/`

The plugin repo is the single source for persona-engine, m3-market and respiro-ios. Change it once,
here; never add a per-repo copy.

## Sequencing

Round 1 (`273da7e9`) is live in this repo right now on `leadv2-state-path.sh`,
`leadv2-dispatch-code.sh` and `leadv2-broad-status.sh`. Do not start until it lands, then build on
it rather than reworking it.

## One more thing to check, not to fix

`plugins/leadv2/scripts/leadv2-broad-status.sh` and `leadv2-review-run.sh` carry **uncommitted
edits dated 2026-08-22** (+49 and +101 lines), alongside three untracked files:
`ZZ-pre-review-run.sh`, `tests/test-broad-status-lanes-blind.sh`,
`tests/test-review-fanout-visibility.sh`. Someone left a day's work uncommitted in the shared
plugin tree. Round 1 is editing `leadv2-broad-status.sh` on top of it. Say in your report what that
work is and whether it should be committed, reverted, or folded in — do not silently discard it and
do not silently keep it.
