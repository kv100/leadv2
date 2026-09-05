# SUITE-SPEED-FIX3 — serial-pin repo-state suites in shard mode (~/Projects/leadv2, lane 74658fef)

State: serial (shards=1) is 60/0 green (1417s). Sharded (8) = 59/2: suites that run dispatch
fixtures against the repo root dirty the SHARED worktree's docs/leadv2 and collide — this
round «fanout classifier/runner guard» + «dispatch refusal fallback chain» (hermetic tripwire:
"dispatch refusal fallback chain dirtied docs/leadv2"), previous round it was the codex
session-runner pair via live HOME (fixed 93f5632). HOME isolation cannot cover repo-root
state.

Fix: add a SERIAL marker to SUITE_DEFS rows (e.g. a 3rd |||SERIAL field) and run marked
suites in a dedicated serial phase AFTER the parallel shards, inside the same flock. Mark at
least: fanout classifier/runner guard, dispatch refusal fallback chain, Codex full-cycle
runner, report-only gate, product-close waits for worker exit, stop-gate autocommit, lane
truth batch, lanes snapshot reconciliation — plus ANY suite whose log shows a
HERMETIC-VIOLATION WARN in /the sharded log (rerun shards=8 yourself FOREGROUND and mark
every violator). Summary line format unchanged; shards=1 behavior byte-identical.

Acceptance: shards=8 run FOREGROUND green (report timing — expect the serial tail to cost
minutes, still far under 1417s) · shards=1 green · red-first leg: a deliberately-marked
fake suite runs after the parallel phase (order assertion). COMMIT before ending.

## Off_limits
Suite assertions/logic; dispatch-code.sh; product-close.sh.

## Terminal artifact
Commit sha + timings + green summaries + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-27debf8c" "<question>" \
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