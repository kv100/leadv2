# `run-core-offline.sh` is red on untouched plugin main — ROUND 2

Repo for this lane: **`/Users/kostiantyn.vlasenko/Projects/leadv2`**. All edits land there.

## Why there is a round 2

Round 1 (`21488ff6`) produced **zero bytes of diff**. Its worker read its own mission, was denied a
single `Read` by a PreToolUse hook, and then answered: *"Developer agent is running in the
background on the `run-core-offline.sh` fix. I'll report back once it completes."* — and ended its
turn. No sub-agent output ever landed, the worktree stayed clean, and the dispatcher closed the lane
`terminal=no_work cause=empty_diff` ten minutes later.

Two things follow, and both are binding on you:

- **Do the work in this session, in this worktree, yourself.** Do not spawn a background agent and
  report that it is running. A lane is judged by the diff in its own worktree at the moment its
  worker exits; work that is "still running somewhere" is work that does not exist.
- **A denied `Read` is not a stop.** `cbm-code-discovery-gate` denies the first code `Read` of a
  session exactly once as a nudge toward the graph tools, then permits everything after. Retry the
  same `Read` and it succeeds. Do not treat it as a permission wall or route around it.

## The defect (unchanged, re-verify before fixing)

On a clean checkout of plugin `main`, with no lane involved:

```
$ timeout 600 bash plugins/leadv2/scripts/tests/run-core-offline.sh
[TEST] FAIL: codex liveness probe called only 2 times
[TEST] FAIL: revived waited to timeout instead of finalizing original handle
rc=124                       # does not finish inside ten minutes
```

Two failing assertions **and** a run that never reports a verdict inside a generous bound — so any
gate running it with `timeout 120` reports it red a second, independent way.

It sits in the `--scope changed` set for a wide range of lanes, so it kills work that did not cause
it. Today it killed `4012b6c5` (two test-file edits, correct, merged by the lead as `2916fe0`) and
`f41dfb1b` (re-dispatch guard). Both lost a full round to a defect they never touched.

## First hypothesis to test — do not assume it

Both failing assertions concern the **codex handle lifecycle**, and codex has been quota-locked
since 2026-08-06. The assertions may be counting probes that no longer happen when the provider is
locked out — i.e. asserting on a path a quota lockout short-circuits. Confirm or refute by
evidence: run the suite with the lockout artificially absent and present, and compare. Change no
assertion before that comparison exists. If the hypothesis is wrong, say so plainly and report what
the instrumented run actually showed.

Separately, find out **why it exceeds ten minutes**. A core offline suite that cannot finish in ten
minutes is a defect in its own right and is the reason nobody noticed the reds: a suite this slow
gets killed rather than read. Note there are older worktrees named `CORE-OFFLINE-CODEX-RECURSION-01`
and `-FIX1` under `.claude/worktrees/` — read them for prior attempts before re-deriving, but do not
branch from them.

## What the fix must achieve

- Green on a clean `main` checkout, or the two assertions corrected to assert what the code actually
  guarantees — with the reasoning written down, never silently relaxed.
- Finishes well inside a normal gate bound. State before and after wall-clock.
- If any part genuinely depends on a live codex quota, that dependency is explicit — a distinct SKIP
  count, never a silent pass and never a red for everyone whenever the provider is locked out.

## Tests

Whatever you change, the assertion must still be able to fail for its original reason: show it red
against a deliberately broken lifecycle, then green.

## Explicitly out of scope

Do not quarantine it in a known-failures list — the plugin has no such registry and inventing one is
a separate decision. Do not raise the gate timeout to hide the symptom. Do not hand-exclude codex
from any pool: routing belongs to quota/task/complexity.

## Hard limits

- Two other suites are red on untouched `main` for unrelated reasons and are not yours.
- Never `git add -A` from the lane worktree — three lanes today would have silently reverted
  `docs/leadv2/open-threads.md`. Stage your paths explicitly.
- No CI runs the unit tier at all, so "the suite is green" means "green on your box" — name the
  platform you ran on, and prefer Linux (the VPS) where the behaviour differs.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-be4c2e83" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.