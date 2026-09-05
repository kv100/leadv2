# COMBO2-FINISH — fix own regressions + item 4 (~/Projects/leadv2, lane 04789baf)

Lane HEAD 96ff69c carries items 1-3 committed (backlog-pump nit 1-A dc6f99d, codex
instant-complete nits f387f4d, CODEX-ARM liveness probe 9d9ffe6, TIERED-REVIEW round-0
fd2be5b) + a STOP-GATE auto-checkpoint of trailing work. Original mission:
docs/handoff/dispatch-04789baf/lane-mission.md.

## 1. Fix the 2 regressions your predecessor introduced (solo-verified red just now):
- tests/test-lane-placement-pin.sh: P-h(g) «prompt pin line MISSING on default
  ensure-created path» + P-h(g2) pin line does not name the worktree — the dispatch-code
  edits (liveness probe / round-0 wiring) dropped or reordered the worktree-pin line
  injection on the default (non --resume-lane) path. Restore it; the pin must name the
  actual worktree path.
- tests/test-stop-gate.sh red in THIS lane — run it solo, read the failing leg, fix the
  interaction (likely the same pin/journal reorder). Product-close itself is OFF-LIMITS —
  if the fix seems to need product-close.sh changes, STOP and write that in the artifact.

## 2. Item 4 (slice-1, spec docs/specs/worker-messaging-v3.md): leadv2-event.sh emitter
(JSONL at ~/.claude/cache/leadv2-events/<repo>.jsonl) + 4 emits in dispatch-code.sh
(worker_spawned, arm_refused, worker_terminal, question_asked). Check the STOP-GATE
checkpoint (96ff69c) — part of this may already exist; finish it. Red-first test.

## Acceptance
test-lane-placement-pin.sh green · test-stop-gate.sh green · own emitter suite green with
red leg · full run-core-offline FOREGROUND SOLO green · bash -n + shellcheck -S warning ·
COMMIT everything (suites strictly solo; on fail rerun solo once).

## Off_limits
leadv2-dispatch-product-close.sh; lib/leadv2-builder-selfcheck.sh (combo-1 lane owns them);
routing; supervise*.

## Terminal artifact
Commit shas + raw green output for both regression suites + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-b8edff8b" "<question>" \
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