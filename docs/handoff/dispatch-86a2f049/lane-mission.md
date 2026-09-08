# The ownership check exists in pieces and is wired in zero repos

**Row C2 of `PRE-WAVES-PLAN.md`**, under the founder's 2026-09-08 order that the plugin repo is
the single source and a project must never hold a real copy of a plugin-owned file.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed
to main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## Why this row exists

The founder's rule is one sentence: **a plugin-owned file lives in `~/Projects/leadv2` and every
project sees it through a symlink.** The failure it prevents is not hypothetical — on 2026-07-29
a product gate landed in canonical, persona-engine's *copy* did not receive it, and persona-engine
is the repo that dispatches. So a gate the founder had been told existed did not exist on the
running path. A copy drifts, and it drifts silently.

Row C1 merged today (`9a04ee3f`): the **producer** no longer writes real copies. That closes the
way new copies are born. It does not tell anyone when one appears by other means — a hand-edit, a
rescue, an `rsync` from an older script, a worktree.

## What is actually there — establish this first, do not trust my list

Candidates the lead found by name; their real behaviour is unverified:

- `plugins/leadv2/scripts/leadv2-e2e-ownership.sh`
- `plugins/leadv2/scripts/leadv2-drift-guard.sh`, `leadv2-one-copy-convert.sh`,
  `leadv2-overrides-drift.sh`, `leadv2-drift-only-vendored-check.py`
- hooks: `plugin-scripts-drift-guard.sh`, `plugin-scripts-drift-session-warn.sh`,
  `leadv2-one-copy-drift.sh`, `leadv2-link-tree-heal.sh`, `leadv2-blocker-drift-guard.sh`

**Answer three questions before designing anything:**

1. **Which of these actually runs today, in which repo, triggered by what?** A hook file existing
   in the plugin tree is not the same as a hook installed in a project's settings. Check the
   installation, not the file.
2. **What does each one check?** Several names suggest the same job. If two check the same thing,
   say which one should survive — this row is partly a consolidation.
3. **Is the claim "wired in zero repos" true?** It is the lead's, and it is the premise of this
   whole row. If any of them IS wired in any of `persona-engine`, `m3-market`, `respiro-ios`,
   **say so and correct the row** — a mission whose premise is wrong is a finding, not a failure.
   The live repos share trees, so check each one's own `.claude/settings.json` rather than
   assuming they match.

## What the fix has to achieve

**A real copy of a plugin-owned file, anywhere in a live repo, is detected and named — every
session, without anyone remembering to look.** Three properties:

- **It names the file and the canonical it shadows.** "Drift detected" is useless; the reader
  must know which inode to delete and what it should have been.
- **It cannot pass by accident.** A check that scans an empty set and prints success is the
  failure mode this repo has already had (a loop over zero items prints success). Print the
  number checked, always.
- **Perimeter includes `leadv2/.claude/scripts`.** That tree is where the shadows have actually
  accumulated — 246 untracked files sit in `.claude/scripts/tests` alone. If widening the
  perimeter makes the check red on day one, that is correct behaviour, not a bug: report the
  count, do not suppress it.

Do not build a new checker if one of the existing five does the job — wire that one and delete
the rest. Say plainly which you chose and why.

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** Plant a real copy of a plugin-owned file in a scratch repo and assert the
   check reports it **by name**, with a non-zero count. Then disable your wiring inside the
   function body and show the suite goes red.
2. **The guard.** A tree with no copies must pass — and the pass must carry the number of files
   checked, asserted as a **value greater than zero**. Mutate the scan so it examines nothing and
   show the suite goes red: a green that means "I looked at nothing" is the thing to prevent.

Insert every mutation **inside the function body**, never at top level.

Register your suite with a `# run-all-triggers: <stem>` header and prove selection with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` printing your `<stem>:<suite>` row.

## Constraints

- **Do not edit the shared trees themselves** (`~/.claude/leadv2-shared`, `~/.claude/scripts`) —
  that is a founder-permission action, not a lane action. Build the check; the lead runs the
  conversion.
- **Do not touch `tests/run-all.sh`** — two other lanes are working in it and I have already lost
  one lane today to that collision.
- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`.
  Never `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.

LANE_WRITES: plugins/leadv2/scripts/leadv2-e2e-ownership.sh, plugins/leadv2/hooks/plugin-scripts-drift-guard.sh, plugins/leadv2/tests/test-ownership-check-names-the-copy.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-86a2f049" "<question>" \
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