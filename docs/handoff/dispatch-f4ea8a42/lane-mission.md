# SUITE-SPEED-FIX2 — shard-mode HOME contention (~/Projects/leadv2, lane 74658fef)

Sharded run (LEADV2_SUITE_SHARDS=8) = 339s, 59 passed / 2 failed. Evidence: the codex
session-runner suite tripped its own tripwire «live ~/.claude/cache/arm-cooldown was touched
by this suite (before/after differ)» — under sharding a SIBLING suite in a parallel shard
touched shared live $HOME/.claude state during its window. TMPDIR isolation (item 2) does
not cover HOME. Identify BOTH failing suites from the full sharded log at commit-time (rerun
sharded once), then fix by ONE of:
(a) per-suite sandbox HOME in shard mode (export HOME=<suite tmpdir>/home with the minimal
    ~/.claude skeleton the suites need) — preferred if suites tolerate it;
(b) a serial-pinned group: suites that read/write live ~/.claude/cache run in a dedicated
    serial phase after the parallel shards (mark them in SUITE_DEFS, e.g. |||SERIAL flag).
Also: the sharded summary said failed=2 but only ONE [CORE-OFFLINE] FAILED: line was printed —
fix the reporting so every failed suite prints its FAILED line under sharding.

Acceptance: shards=8 run green (report timing), shards=1 green (parity), the tripwire suite
passes in both modes, deliberate concurrent second serial run still refused/queued by the
flock. FOREGROUND, COMMIT before ending.

## Off_limits
Suite assertions/logic (fixture+runner mechanics only); dispatch-code.sh; product-close.sh.

## Terminal artifact
Commit sha + both timings + green summaries + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-f4ea8a42" "<question>" \
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