# SCOPE-DISCIPLINE-ONLY-01 — single item (~/Projects/leadv2, lane 201b3f97)

ONE task only. Lane checkpoint 5b35a06 contains ~148 lines of builder-selfcheck work from a
prior attempt — READ IT FIRST (git show 5b35a06), judge and reuse or replace.

SCOPE-DISCIPLINE-01: in the builder-selfcheck gate (lib/leadv2-builder-selfcheck.sh + its
product-close call site), a diff that touches paths OUTSIDE the declared write-set
(LEADV2_DISPATCH_LANE_WRITES / _PC_SCOPE_WRITES_CSV, already parsed in product-close) =
builder BOUNCE before any review arm, with a journal line naming the offending paths.
Bounce, never silently trim. Kill-switch env (same idiom as LEADV2_BUILDER_SELFCHECK).
Red-first test in tests/ registered in run-core-offline.sh.

DO NOT background anything. Run every command in the FOREGROUND. Do not idle-wait on any
process. Suites strictly solo. COMMIT on the lane branch before ending.

## Acceptance
Own suite green with red leg shown · full run-core-offline FOREGROUND SOLO green ·
bash -n + shellcheck -S warning · COMMIT.

## Off_limits
leadv2-dispatch-code.sh; routing; supervise*; everything outside builder-selfcheck +
product-close call site + tests.

## Terminal artifact
Commit sha + red/green raw output + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-57a89259" "<question>" \
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