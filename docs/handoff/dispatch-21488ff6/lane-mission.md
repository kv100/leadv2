# `run-core-offline.sh` is red on untouched main and has killed two lanes today

Repo for this lane: **`/Users/kostiantyn.vlasenko/Projects/leadv2`**. All edits land there.

## The defect

On a clean checkout of plugin `main`, with no lane involved:

```
$ timeout 600 bash plugins/leadv2/scripts/tests/run-core-offline.sh
[TEST] FAIL: codex liveness probe called only 2 times
[TEST] FAIL: revived waited to timeout instead of finalizing original handle
rc=124                       # the run does not finish inside ten minutes
```

Two failing assertions **and** it exceeds a 600s bound, so it never even reports a verdict on a
generous timeout — and any `timeout 120` reports it as a failure a second, independent way.

It is in the `--scope changed` set for a wide range of lanes, so it kills work that did not cause
it. Today it killed `4012b6c5` (two test-file edits, correct, merged by the lead as `2916fe0`) and
`f41dfb1b` (re-dispatch guard). Both lanes lost a full round to a defect they never touched.

## First hypothesis to test — do not assume it

Both failing assertions are about the **codex handle lifecycle**, and codex has been out of quota
since 2026-08-06. The assertions may be counting probes that no longer happen when the provider is
locked out, in which case the test is asserting on a code path that a quota lockout short-circuits.
Confirm or refute with evidence — run the suite with the lockout artificially absent and present
and compare — before changing any assertion. If the hypothesis is wrong, say so and report what the
instrumented run actually showed.

Separately, find out **why it takes over ten minutes**. A core offline suite that cannot finish in
ten minutes is a defect in its own right, independent of the two failures, and it is the reason
nobody noticed the reds: a suite this slow gets skipped or killed rather than read.

## What the fix must achieve

- The suite is green on a clean `main` checkout, or the two assertions are corrected to assert what
  the code actually guarantees — with the reasoning written down, not silently relaxed.
- It finishes well inside a normal gate bound. State the before and after wall-clock.
- If any part of it genuinely depends on a live codex quota, that dependency must be explicit
  (skip with a distinct SKIP count, never a silent pass) rather than making the suite red for
  everyone whenever the provider is locked out.

## Explicitly out of scope

Do **not** quarantine it by adding it to a known-failures list — the plugin has no such registry
and inventing one here is a separate decision. Do not raise the gate timeout to make the symptom
go away. Do not hand-exclude codex from any pool: routing belongs to quota/task/complexity.

## Tests

Whatever you change, the assertion must still be able to fail for its original reason — show it
red against a deliberately broken lifecycle, then green.

## Hard limits

- Note two other suites are red on untouched `main` for unrelated reasons and are not yours.
- Never `git add -A` from the lane worktree — three lanes today would have silently reverted
  `docs/leadv2/open-threads.md`. Stage your paths explicitly.
- No CI runs the unit tier at all, so "the suite is green" means "green on your box" — say which
  platform you ran on, and prefer running it on Linux (the VPS) where the behaviour differs.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-21488ff6" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.