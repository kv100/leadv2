# CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01 — fix round 2

Item 1 landed and is accepted — commit `468d98bb`. `flag_source` is an explicit field, and
`FLAG_SOURCE_PRIORITY` is a single ordered list with `path` first and the reason it is not yet
available written next to it. Do not redo it, do not restructure it.

Your worker died before items 2 and 3. Both remain, and item 2 is the blocking one.

## 1. Negative controls — blocking

`tests/test-leadv2-task-judge.sh` is green. Green proves the suite runs; it does not prove the suite
**bites**. Two of five wave-3 lanes closed tonight, and each closed only because a mutation made its
suite go red. This lane will be held to the same bar.

Read `plugins/leadv2/scripts/tests/nc-claude-account-collapse.sh` on main as the model — it is now
merged, so it is in your tree. Required properties, all of them:

- The mutation is applied **inside a function body**, never at file top level. A top-level insert
  reddens every suite for the wrong reason and reads as a pass.
- The mutated copy is written to a scratch file and the suite runs against **that copy** via an
  injection variable; never edit the original in place.
- An `NC-SETUP-FAIL` guard that exits non-zero loudly if the target line no longer matches, so the
  control cannot silently degrade into mutating nothing.
- The control passes **only** when the suite goes red.

Two controls, one per claim:

- **NC1 — the prose collision is really gone.** Inside the matcher, restore the old behaviour:
  substring-match the path globs against mission prose. The suite must go red. This is the defect
  the lane exists to fix; with no assertion catching its return, nothing is proven.
- **NC2 — the genuine safety task is still caught.** Inside the resolver, make the selected
  `flag_source` always yield no match. The suite must go red on the one real safety task. Without
  this, "we stopped the false positives" could have been achieved by matching nothing at all, which
  is formally correct and operationally catastrophic.

For each: report the `baseline_rc` / `mutated_rc` pair and the literal red suite line, then revert and
show green with both exit codes pasted. A `diff_hash` is not proof that anything ran.

## 2. The closure must carry the temporary line

Write into the closure, explicitly: **keying on id and title is temporary.** It exists because
`LANE_WRITES` is empty in 237 of 241 dispatches; the founder's decision is that protection is
determined by write paths, and the switch to `flag_source=path` happens when
`LANE-WRITES-IS-EMPTY-98-PERCENT-01` is closed. Name that row by id so the next reader can find it.

A closure presenting the title-based matcher as the intended design will be read as settled, and
nobody will come back to it.

## 3. Registration — prove it, do not assert it

If your suite is registered in `tests/run-all.sh`, prove the runner selects it the way both closed
lanes did, with the non-executing seam:

```
LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
```

Make a **real edit** to `leadv2-task-judge.sh` first — `touch` does not work, git does not see it and
the proof comes back falsely empty. Revert the edit afterwards and confirm the tree is clean. Paste
the `[SELECT] …` line for your suite.

## Constraints

- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — held by another session.
- Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened to reach green.
- **Append only** in `tests/run-all.sh` — do not reformat or move existing rows. Two other lanes
  merged registrations into that file tonight and a lost row disappears silently.
- **Commit after each item.** Workers on this repo have died five times tonight between 10 and 14
  minutes in, every time before committing; the cause is unknown and unfixed. Your predecessor on
  this lane survived long enough to commit item 1, which is the only reason it is not being redone.
  Commit early and often — that is the difference between progress and a rescue.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-ac7b08fc" "<question>" \
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