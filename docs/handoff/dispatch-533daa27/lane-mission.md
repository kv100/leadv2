# LANE-WRITESET-REGISTRY-01 — wire the write-set registry onto the live single-lead path

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (canonical plugin source). Never edit
through a consuming repo (persona-engine / m3-market / respiro-ios) — those are symlinks.

## Read the plan first, it is binding
`docs/handoff/LANE-WRITESET-REGISTRY-01/context.yaml` — decisions D1–D9, 9 plan steps,
off_limits, risk, verification.live_signal, test_plan. Implement THAT plan. If you want to
diverge from a decision, stop and return `BLOCKED` naming the decision id and your reason.

## Outcome (one)
Two concurrent lanes that declare an intersecting write set cannot both be admitted: the
second `register` is refused ATOMICALLY, inside the registry's existing flock, before any
worker is spawned. Plus the `/leadv2 sessions` peer merge and the close-time peer notify.

## The headline the plan establishes — do not re-derive it
The registry already exists end to end (`set_writes` op, `leadv2-writes-overlap.sh`, its
5-case suite) and is DEAD on the live path: its only callers are the retired
`leadv2-fanout.sh`. `leadv2-dispatch-code.sh` already resolves the declared `writes` CSV and
already scopes the review diff with it — the value simply never reaches active.yaml. This is
three wires plus one atomicity fix, not a new subsystem.

## Hard constraints
- The intersect and the append happen in ONE flock acquisition (D3). A shell-level
  check-then-register is a TOCTOU race and makes the whole gate decorative under exactly the
  concurrency it exists for. This is the single most important line in the task.
- Keep the existing `writes` key; do NOT introduce `write_set` as the written key (D1).
- The BLOCK decision does NOT live in `leadv2-writes-overlap.sh` — that script stays
  fail-open and byte-compatible; `LEADV2_WRITES_CONFLICT_NOTIFY=0` must never be able to
  turn the safety gate green (D4).
- A row with no `writes` is the third state `unknown` — never silently "conflicts with
  everything" nor "conflicts with nothing" (D7). rc=5 conflict, rc=6 unknown, distinct.
- `LEADV2_WRITESET_ENFORCE` defaults to `warn` for the soak. The flip to `block` is the
  one-line change and the one-line rollback.
- Register gains a positional arg ADDITIVELY with a default, so every existing caller in all
  three repos keeps working unchanged.
- Parts 2 and 3 split at the process boundary (D8): shell renders and persists, the LEAD
  relays via ListAgents/SendMessage. Do not write bash that "calls ListAgents" — it cannot.

## Mandatory: E2E-KILLRATE-01
1. Run `verification.live_signal` from the plan verbatim and paste its output. It is marked
   UNVERIFIED (design-time) — you are the one who makes it real. If it does not pass as
   written, fix the test or the code and say which.
2. The declared negative control from `test_plan.negative_control`: change the overlap
   predicate to never match, INSIDE the function body, in a scratch worktree. Show the suite
   goes RED. Paste the run output. A top-level insert reddens everything for the wrong
   reason and reads as a pass — do not do that.
3. CI must SELECT the new suite: add the row to the array in
   `plugins/leadv2/scripts/tests/run-core-offline.sh` and prove selection by showing the
   label in the runner's own output.
4. Append-only on `test-writes-overlap.sh` — its 5 cases are the fanout regression baseline.

## Acceptance
- `live_signal` passes with output pasted (rc=5, conflict message, and LANE-B NOT appended).
- Negative control RED-without / GREEN-with, output pasted.
- New suite visibly selected by the runner.
- One-line rollback named.

Return `PASS|FAIL|BLOCKED` + changed paths + commit SHA + raw test output.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-533daa27" "<question>" \
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