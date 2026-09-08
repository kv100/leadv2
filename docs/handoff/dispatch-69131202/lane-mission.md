# 64 override files, 24 of them with no reader — and no proof that any is safe to delete

**Row C4 of `PRE-WAVES-PLAN.md`**, filed as `ONE-PLUGIN-SOURCE-TRIAGE-THE-64-OVERRIDES-01`.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not committed
to main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

---

## Why this row exists

Two design arms audited the override surface and disagreed about what may be deleted.

- **fable** counted **24 of 64** override files with zero readers anywhere in the plugin, and
  proposed deleting those and schema-ing the other 40.
- **astra** refused the count as a deletion authority: `gemini-policy.yaml` has no reader in a
  bounded static scan and *is* a retire candidate — but a static grep does not see a dynamic
  policy loader. And `golden/bandit-sample-seeded.json` looks redundant and is not: it is a
  blocked evaluation artifact whose engine went missing.

The lead sided with astra on method and with fable on the worklist: **fable's 24 is the candidate
list; astra's per-file proof is the gate each candidate must pass.** No row authorises deletion on
a static grep alone. Detail: `docs/handoff/SMART-ARBITER-DESIGN-20260907/ONE-PLUGIN-SOURCE-RECONCILIATION.md`
§B.

## What this lane delivers — and what it does NOT

**Delivers:** a machine-checkable per-file verdict table, and a checker that can re-derive it.

**Does NOT delete anything.** Deletion is a lead action after reading your table. A lane that
removes config files is exactly the irreversible-destruction case the founder's standing order
excludes. Propose; do not execute.

## Establish the census first — do not trust the number 24

The number came from one arm's bounded scan and it may be wrong in either direction. Re-derive it
yourself, and say plainly what the real count is. The override surface spans more than one repo:
`persona-engine`, `m3-market`, `respiro-ios` each carry their own `.claude/leadv2-overrides/`, and
they do **not** have to agree. Report per-repo, never a single blended number — a blended count is
the kind of boundary-less number that has already misled this project.

## The per-file proof each candidate must pass

A file may be listed as `RETIRE` only when all four are recorded:

1. **Consumer** — the file:line that reads it, or the explicit finding that none exists.
2. **Dynamic-loader search** — a search for loaders that build a path at runtime (a variable
   filename, a glob, a `for f in "$dir"/*` loop), not only for the literal basename. State what
   you searched for. This is the step that separates this row from the static grep that produced 24.
3. **Absent-file default** — what the consumer does when the file is missing. A file whose absence
   changes behaviour is not dead, however few readers it has.
4. **Recorded session read** — evidence from a real session/journal/log that the file was or was
   not actually read. "Configured" is not "executed", and the reverse is also true: a file with no
   static reader that shows up in a session read is **alive**.

Anything short of all four is `UNPROVEN`, not `RETIRE`. `UNPROVEN` is a perfectly good verdict and
must not be rounded down.

Write the table to `docs/handoff/one-plugin-source/override-triage.md` and, machine-readable, to
`plugins/leadv2/config/override-triage.yaml` (one entry per file: repo, path, verdict, consumer,
absent_default, evidence). The yaml is what the checker reads.

## The checker

`plugins/leadv2/scripts/leadv2-override-triage.sh` re-derives verdicts and compares them to the
yaml. It exists so this table cannot rot silently: a file that gains a reader after you write the
table must stop reading `RETIRE`.

Two properties, both non-negotiable:

- **It prints the number of files examined, always.** A loop over zero items that prints success is
  a failure mode this repo has already had. `checked=N` on every run, and `N=0` is a failure, not a
  pass.
- **It names the file and the disagreement.** "Triage stale" is useless; the reader must know which
  path changed verdict and what it changed from.

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** Take a file the yaml marks `RETIRE`, plant a real reader for it in a scratch
   copy of the tree, and assert the checker reports that file **by name** and exits non-zero. Then
   disable your comparison inside the function body and show the suite goes red.
2. **The guard.** A tree whose readers match the yaml must pass — and the pass must carry
   `checked=N` asserted as **greater than zero**. Mutate the scan so it examines nothing and show
   the suite goes red: a green meaning "I looked at nothing" is the thing to prevent.

Insert every mutation **inside the function body**, never at top level.

Register your suite with a `# run-all-triggers: <stem>` header and prove selection with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` printing your `<stem>:<suite>` row. That
command is stateless and is the only selection oracle — do not use `--scope changed`.

## Constraints

- **Delete nothing.** Not one override file, in any repo.
- **Do not edit the shared trees** (`~/.claude/leadv2-shared`, `~/.claude/scripts`) — founder-permission
  territory, not a lane action.
- **Do not touch `tests/run-all.sh`** — a live lane holds it and I have lost two lanes today to that
  collision.
- Do not merge. Report; the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`.
  Never `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.

LANE_WRITES: plugins/leadv2/scripts/leadv2-override-triage.sh, plugins/leadv2/config/override-triage.yaml, plugins/leadv2/tests/test-override-triage-names-the-live-file.sh, docs/handoff/one-plugin-source/override-triage.md

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-69131202" "<question>" \
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