# `--scope changed` lies in three separate ways

**Row B6 of `PRE-WAVES-PLAN.md`.** It produced two wrong conclusions in a single day, both
by the lead, both about whether a test suite was registered for CI selection.

REPO: `~/Projects/leadv2`. Its `main` IS the live path — symlink deploy, so a fix not
committed to main is not delivered. **Dispatch and work from `~/Projects/leadv2`.**

Already filed as rows `SCOPE-CHANGED-IS-STATEFUL-AND-A-SECOND-RUN-LIES-01` and
`SCOPE-CHANGED-DEGRADES-TO-THE-LAST-COMMIT-01`. Read both before designing; if your fix
subsumes one, say so explicitly rather than leaving two half-overlapping rows.

---

## The three lies, as observed. Verify each against the source before you build.

In `tests/run-all.sh`:

- **(a) It counts from a checkpoint file, not from the merge base.** When
  `$GIT_DIR/leadv2-run-all-last-checked-sha` exists, the range starts there (`:294-310`).
  A second run therefore sees a *different* change set than the first, and a suite that
  was correctly selected the first time can look unselected the second.
- **(b) With no checkpoint and no resolvable base ref it degrades to `HEAD~1..HEAD`** —
  the last commit only (`:308-317`). On a branch with several commits this silently
  examines a fraction of the work.
- **(c) Consequently the instrument is not trustworthy in either direction**: a correctly
  registered suite can look unregistered, and a broken registration can look fine.

Line numbers are from the lead's reading and may have moved — re-locate them, and if the
mechanism differs from this description, **report the difference rather than fitting the
code to the story**. A mission that turns out to be wrong is a finding, not a failure.

## What the fix has to achieve

**A selection query answers the question the caller actually asked, or refuses.** Three
properties, and the third is the one that matters most:

1. **Deterministic for a stated range.** Asking "what does this branch's work select"
   must give the same answer twice in a row, and must not depend on residue from an
   earlier run.
2. **No silent degradation.** If the base ref cannot be resolved, that is a refusal with a
   named reason — never a quiet fallback to `HEAD~1..HEAD` that returns a plausible,
   wrong answer. A wrong answer that looks right is the whole defect here.
3. **The checkpoint keeps working for the case it exists for.** Incremental CI runs are a
   legitimate use — do not delete the mechanism to fix the interrogation case. Distinguish
   "what changed since we last ran" from "what does this branch change", and let the caller
   say which one they mean.

Note the honest alternative you should weigh: the lead has stopped using `--scope changed`
for selection proofs entirely and uses `LEADV2_RUN_ALL_LIST_TRIGGERS=1` instead, which is
stateless and direct. If your conclusion is that `--scope changed` should stay as-is for CI
and simply never be used as a selection oracle, argue that — but then the fix is a refusal
or a warning when it is used that way, not silence.

## Negative controls (E2E-KILLRATE-01, non-negotiable — two, both run, red then green)

1. **The symptom.** Run the same selection query twice with a checkpoint present from the
   first run; the second answer must equal the first. Assert on the **selected set**, not
   on a log line. Then re-introduce the stateful read inside the function body and show the
   suite goes red.
2. **The guard.** An unresolvable base ref must **refuse with a named reason**, not return
   a set. Mutate your refusal into the old silent fallback and show the suite goes red —
   otherwise the fix cannot tell a refusal from a plausible wrong answer, which is exactly
   today's bug.

Insert every mutation **inside the function body**, never at top level: a top-level insert
reddens everything for the wrong reason and reads as a pass. That mistake has already
invalidated one measurement in this repo.

Register your suite with a `# run-all-triggers: <stem>` header and prove selection with
`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh` printing your `<stem>:<suite>` row.
**Do not prove selection with `--scope changed`** — proving a broken instrument with itself
is how this row was born.

## Care required

`tests/run-all.sh` is the runner every other lane's proof depends on. A regression here
makes every suite in the repo unselectable and no single lane would notice. Change the
minimum, keep the existing callers working, and state in your report which callers you
checked and how.

## Constraints

- Do not merge. Report, and the lead verifies and merges.
- Never push to origin. Never `reset --hard`, `clean`, `stash`, or `worktree prune`.
  Never `git add -A` — enumerate paths.
- Report `main...HEAD` (three dots), never `main..HEAD`.

LANE_WRITES: tests/run-all.sh, plugins/leadv2/tests/test-scope-changed-is-deterministic.sh

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-e9f5e371" "<question>" \
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