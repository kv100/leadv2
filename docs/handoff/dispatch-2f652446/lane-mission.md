CODEX-CONFIG-GROWS-FOREVER-01. Every lane worktree appends a table to `~/.codex/config.toml` and
nothing ever removes one. The file is now 1.66 MB / 45027 lines / 7489 `[projects."…"]` tables,
7422 of them worktrees, and codex parses the whole thing on every start.

REPO: ~/Projects/leadv2. Founder order 2026-09-08: "сделай так чтобы кодекс всегда работал."

## Measured 2026-09-08T00:4xZ

    wc -l ~/.codex/config.toml            -> 45027
    ls -l  ~/.codex/config.toml           -> 1662780 bytes
    grep -c '^\[projects\.' …             -> 7489
    grep -c 'worktrees' …                 -> 7422

The writer is `plugins/leadv2/scripts/leadv2-lane-worktree.sh:383`: it appends
`[projects."<abs path>"] trust_level/approval_policy/sandbox_mode/network_access` for each new lane
worktree so codex trusts that cwd. Append-only, no dedup, no prune. Two tables get written for the
same tree when the path resolves both ways — the tail of the file holds
`/var/folders/…/T//dispatch-ledger-…/repo/.claude/worktrees/0020a004` AND its `/private/var/…`
twin, and the temp dir under them no longer exists.

This is not cosmetic. Upstream openai/codex#24048 has the app-server growing to ~27 GB and being
SIGKILLed under large inputs, with no config knob and no maintainer response; a 1.66 MB config
parsed at every start is on the same side of that ledger. It also grows without bound: every lane
we ever run makes the next codex start slower, forever.

## What to build

1. **A prune command.** Remove every `[projects."<path>"]` table whose path does not exist on
   disk, and de-duplicate the `/var` vs `/private/var` twins of the same real path. It must be
   comment-preserving and it must never touch a table for a path that still exists — the
   long-lived project entries (`~/Projects/persona-engine`, `~/Projects/leadv2`,
   `~/Projects/respiro-ios`, and the non-worktree entries at the head of the file) are load-bearing
   and are what makes codex trust the real repos.
2. **Stop the unbounded growth at the writer.** `leadv2-lane-worktree.sh` must not append a table
   that is already present for the same real path, and must write the resolved (`realpath`) form
   once rather than both spellings. Decide and state in the commit message whether a lane's table
   is also removed when its worktree is removed — if you make removal automatic, it must be
   idempotent and must never remove a table for a live worktree.
3. **Back the file up before the first prune** (`~/.codex/config.toml.bak-<stamp>`) and say in the
   report how many tables were removed and how many remain. Do NOT delete the backup.

## Acceptance
acceptance:
  surface: command_output
  observable: `grep -c '^\[projects\.' ~/.codex/config.toml` drops by the number the prune
    reports, `codex --version` still succeeds afterwards, and a REAL dispatch into a NEW lane
    worktree still gets a trusted cwd — shown by the lane actually running codex, not by the
    table existing. Then run the same new-lane dispatch TWICE against the same worktree and show
    the table count did not increase the second time.

## Negative controls (E2E-KILLRATE-01) — run them and SHOW them red
1. Inside the prune function body, make the existence check always true (treat every path as
   present). The suite must go red on the COUNT of surviving tables for a fixture containing a
   known-dead path — the number, not a log string.
2. Inside the writer's dedup body, always append. The suite must go red on the table count after
   a second write of the same path. Without this control the dedup is a comment.
Insert each mutation INSIDE the function body, never at top level — a top-level insert makes every
suite red for the wrong reason and reads as a pass. Point the suite at a FIXTURE config, never at
the real `~/.codex/config.toml` (`CODEX_HOME` or an explicit path parameter). A suite that mutates
the developer's live codex config is itself a defect. Self-register with
`# run-all-triggers: leadv2-lane-worktree` and verify with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh`; do NOT edit `tests/run-all.sh`.

## Constraints
- Do NOT touch `codex-task.sh` (a sibling lane owns it), `leadv2-dispatch-code.sh`,
  `lib/leadv2-route-arbiter.sh`, `config/leadv2-routing.yaml`. Read them freely.
- Do NOT edit `~/.claude/plugins/cache/openai-codex/**` (upstream tree).
- Never `git add -A`. **`git commit -- <path>` commits the WORKING TREE for that path, not the
  index.** Stage explicitly, check `git diff --cached --stat`, then commit WITHOUT a pathspec.
- Never `reset --hard`, `clean`, `stash`, `worktree prune`. Never push to origin.
- Every claim carries its artifact: a count, a command output, a suite run. Say "unverified" out
  loud; never say "should work".

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-worktree.sh, plugins/leadv2/scripts/leadv2-codex-config-prune.sh, plugins/leadv2/scripts/tests/test-codex-config-prune.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-2f652446" "<question>" \
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