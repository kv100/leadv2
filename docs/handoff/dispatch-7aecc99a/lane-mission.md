# CONTROL-PLANE-FILES-CONFLICT-ON-EVERY-OLD-BRANCH-01 — make salvaging a branch mechanical

Repo: `~/Projects/leadv2` (shared plugin tree). Founder standing permission is recorded at
`persona-engine/.claude/leadv2-overrides/extensions.md:748`; the approved scope is this task only.

Seventeen branches carry real, committed work that never reached `main`. Another lane is moving them
by hand and has died twice doing it. **Your job is not to move branches — it is to remove the reason
moving them is manual.** Two defects, both measured 2026-09-04 by `persona-engine-3a`.

## Defect 1 — every old branch conflicts on the control plane, and resolving it destroys a symlink

All seventeen conflicts land on the same paths:

    docs/leadv2/active.yaml   bus.jsonl   merge-queue.jsonl   open-threads.md   questions
    docs/leadv2/.bus-offsets  .bus.lock   .merge.lock         active.yaml.lock

On `main` these are **symlinks** (mode `120000`) into `~/.claude/leadv2-state/leadv2/`. Old branches
carry them as ordinary files, committed before the control plane moved out of the tree. Every merge
therefore conflicts, and both obvious resolutions — take-theirs or checkout-ours — replace the
symlink with a regular file. `active.yaml` had to be restored **five times in one session**.

Direction (the other lead's, and it is sound): a `.gitattributes` merge driver pinning these paths to
`ours`, so the tree's symlink always wins, **plus a guard that fails loudly** when the count is wrong.

The guard is the part that must not be skipped: a merge driver that silently does the right thing is
indistinguishable from one that silently does nothing. The invariant is exact and already in daily
use by both leads:

    find docs/leadv2 -maxdepth 1 -type l | wc -l   →   16

## Defect 2 — the salvage tool reports failure and exits 0

`leadv2-lane-salvage.sh` prints `verdict=conflict carried=0/4` and returns **exit code 0**. Any
caller — a script, a lane, a CI step — reads success. This is the mirror image of the disease we
spent today on: there, a record was absent and the absence was read as a fact; here the record is
present, explicit, and the exit code contradicts it. Make the exit code carry the verdict.

While you are in that file, check every other exit path for the same shape and report what you find;
do not fix beyond this task's scope without saying so.

## Acceptance — behavioural, with a negative control

1. **A real old branch merges without hand-holding.** Pick one of the seventeen, merge it with the
   driver in place, and show: no control-plane conflict, and the symlink count still 16. Name the
   branch and paste the count.
2. **The guard actually fires.** Break the invariant deliberately (replace one symlink with a regular
   file) and show the guard fails. A guard never observed failing is not known to work.
3. **The exit code tells the truth.** Show `verdict=conflict` with a non-zero exit, and a successful
   carry with zero. Both directions — a tool that always fails is as useless as one that never does.
4. **Negative control, mandatory, inside a suite**, anchored by regexp inside the function body,
   artefact under `mutation-control/` with `anchor= baseline_rc= mutated_rc= red_line=`. A hand
   demonstration will be rejected — that objection already cost another lane a full round today.
5. **`# run-all-triggers:`** naming `leadv2-lane-salvage.sh`, plus a selection proof taken by
   touching a **production** file, never the suite itself (a dirty suite selects by its own
   filename — a false green the other lead has already sat on). Use
   `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`.

## Constraints and traps (measured today — do not re-derive)

- **Never run the full `tests/run-all.sh` in a live checkout**: it redirects five control-plane
  symlinks into a temp dir and deletes their targets. `SELECT_ONLY=1` always.
- **Never `git add -A`** — the checkout carries other sessions' live control-plane files and foreign
  `docs/handoff/*/phases.d/*.yaml`. Stage by path.
- **Never `git checkout --` a control-plane path to clear a merge**: those files are the live state
  of other running sessions, not noise. If a merge is blocked by them, merge from the other side
  (branch into `main` from the main checkout) rather than discarding them. That is how the
  `WRITESET-...` lane landed today.
- **Silence kills you:** `STALL_KILL idle_s=1822 limit_s=1800`. Print a line at least every 10
  minutes. Do not go off to wait for a background run — background completions wake the lead, not
  the worker, and a waiting worker is a dead worker.
- **Touching a file outside your declared write set makes the guard commit NOTHING**
  (`foreign_dirty=undeclared_lane_writes` → `auto_committed=0`). Declare wide enough up front.
- A `no_work` verdict is not evidence of an empty branch: check `git diff --stat main...HEAD` first.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-7aecc99a" "<question>" \
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