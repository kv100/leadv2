# Retire the copy producer: plugin sync goes link-only

**Priority 0.** Step **1 of 5** of the founder's one-plugin-source order (2026-09-08), and the step
every other step depends on. Section C1 of `PRE-WAVES-PLAN.md`.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed to
main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## Why this is first, and what it is not

The founder's framing was «в проектах разные копии плагина». Two independent design arms (fable,
codex/astra) each measured the tree and each found the same thing, separately, and it is *not* the
framing:

- **The project trees are almost entirely symlinks already** — zero shadow copies in two of the
  three active repos, one in respiro-ios. The projects are not the problem.
- **The copies have a live producer, and it is the plugin's own sync script.** The shadow trees
  (`leadv2/.claude/scripts`, `~/.claude/leadv2-shared/scripts`, `~/.claude/scripts`) are *rsync
  targets* of `leadv2-plugin-sync.sh`. An rsync target drifts between `--write` runs by
  construction. Astra put it as: "a copy-producing writer still exists… deleting that directory
  while leaving its producer intact would reproduce the problem."

That is why the conversion (332 drifted shadows → symlinks, ledger row `SD-SYMLINK-FARM-CONVERT-01`)
is step **3** and not step 1. A cleanup that leaves the producer running buys a few weeks.

Census, astra's full recursive count — use these, not the smaller numbers in fable's report or in
my own earlier one, both of which undercounted: **563 real files, 477 shell, 476 shadows,
332 drifted, 21 symlinks.**

**Founder decision, binding, already made — do not relitigate it:** symlinks are the destination
(fable's end state). Astra's export manifest / closed schema is **not** being built. Detail:
`~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/ONE-PLUGIN-SOURCE-RECONCILIATION.md`.

---

## The target, precisely

`plugins/leadv2/scripts/leadv2-plugin-sync.sh` declares six destinations in its own header
(`:5-11`). Their modes differ today and that difference is the whole task:

| | destination | today |
|---|---|---|
| (a) | `~/.claude/plugins/cache/leadv2-local/leadv2/0.1.0/` | rsync |
| (b) | `~/.claude/leadv2-shared/` | rsync |
| (c) | `<project>/.claude/scripts/` | **already link-mode** — `_link_project_scripts` at `:318`, called from `:773` |
| (d) | `<project>/.claude/contracts/` | `cp -p` schema files |
| (e) | `~/.claude/scripts/` | rsync, ADDITIVE (no `--delete`) |
| (f) | `~/.codex/skills/source-command-leadv2/` | rsync |

**(c) is the precedent and it already works.** The task is to make (b) and (e) behave the way (c)
does, and to decide honestly what (a), (d) and (f) should be — they are not obviously the same
case, and I am not going to pretend I know:

- **(a) the plugin cache.** `CLAUDE.md` states that `~/.claude/plugins/local/leadv2/plugins/leadv2`
  is a **symlink** to `~/Projects/leadv2/plugins/leadv2` (same inode), and that the
  `~/.claude/plugins/cache/leadv2-local/leadv2/<ver>/` dirs are "an inert historical snapshot the
  runtime never reads". **Verify that claim before acting on it.** If the cache is genuinely never
  read, syncing to it is pure copy-production and it should stop entirely rather than become links.
  If something does read it, say what.
- **(d) contracts.** Schema files, `cp -p`, with a backward-refusal path (`:535-567`) that exists
  because a project-side copy could be newer. Under a symlink there is no "newer copy" and that
  machinery becomes dead — check whether it can go, and do not delete it in the same commit if it
  cannot.
- **(f) the Codex skill dir.** `~/.codex/` is not ours; a symlink into our repo may or may not be
  acceptable to the Codex runtime. Test it rather than assuming either way.

There is also an exceptions mechanism — `_load_plugin_sync_exceptions` / `_is_plugin_sync_exception`
(`:141-159`, used at `:343` and `:810`) — that already lets specific paths opt out of syncing.
Read it before inventing a new one; the answer may be that link-mode reuses it.

---

## What the fix has to achieve

**After this lands, a `--write` run of the sync script creates no new real copy of a plugin-owned
file in any destination it converts.** That is the acceptance criterion.

Definition of plugin-owned, from the founder's decision, and it is a command not a heuristic:

> a file is plugin-owned **iff** its relative path exists in canonical git —
> `git -C ~/Projects/leadv2 ls-files plugins/leadv2/<kind>/<rel>`. Name prefixes decide nothing.

What it must not do:

- **It must not break a running system.** These trees are on the live path right now, this session
  and every lane is reading from them. A conversion that leaves a destination momentarily absent
  breaks whatever reads it at that instant. Say how you sequence it.
- **It must not convert files that are NOT plugin-owned.** Every repo has 20–40 repo-native scripts
  of its own; those stay real files and stay where they are. A conversion that swallows them is
  data loss.
- **It must not silently do nothing.** A "link-only" mode that skips when it cannot link, and logs
  nothing, is worse than the rsync — it looks converted and is not.
- **It must not convert the 332 existing drifted shadows.** That is step 3, it is a separate ledger
  row, and it is condition-bound on no live worktrees — a condition that is emphatically not
  satisfied today (200+ live lane worktrees). This step only stops the *producer*; existing copies
  stay put and are handled later.

---

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** A `--write` run against a destination you converted must leave a symlink where
   it previously left a real file. Before your change this must FAIL. Assert the **filesystem
   fact** — `test -L`, and that the link resolves into `plugins/leadv2/` — not a log line.
2. **The guard.** A file that is NOT plugin-owned (not in `git ls-files plugins/leadv2/...`) must
   remain a real file and must not be replaced by a link. Break your own ownership test
   deliberately (treat everything under the destination as plugin-owned) and show the suite goes
   red on a value. Without this control the fix is a script that turns a project's own scripts into
   dangling links.

Insert every mutation **inside the function body**, never at top level: a top-level insert reddens
everything for the wrong reason and reads as a pass. That mistake has already invalidated one
measurement in this repo.

Register your suite with a `# run-all-triggers: leadv2-plugin-sync` header. **Then prove selection
correctly** — `--scope changed` lies in three ways:

- it counts from `$GIT_DIR/leadv2-run-all-last-checked-sha` when that file exists (`:294-310`);
- with no checkpoint and no resolvable base ref it degrades to `HEAD~1..HEAD` (`:308-317`);
- so a correctly registered suite can look unregistered, and a broken one can look fine.

Pin the range to the merge base for the proof (write the merge-base sha into the checkpoint file,
run, then remove it) and state in your report which range you measured from.

---

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`. Never
  `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.
- **Do not run `--write` against the live user trees to test.** Build a fixture root and point
  `--project-root` at it. One live run at the end, if you need it, and say so.
- Do not touch `~/.claude/settings.json` or any permission file.
- If your work implies that step 3's ledger row (`SD-SYMLINK-FARM-CONVERT-01`) needs different
  wording, say so in the report — do not edit the ledger yourself.

LANE_WRITES: plugins/leadv2/scripts/leadv2-plugin-sync.sh, plugins/leadv2/tests/test-plugin-sync-is-link-only.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-72e5cf0e" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.