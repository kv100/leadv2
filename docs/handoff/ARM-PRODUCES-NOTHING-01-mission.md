# ARM-PRODUCES-NOTHING-AND-CHAIN-NEVER-ADVANCES-01 — a silent arm burns a whole lane

**Repo to change: `~/Projects/leadv2` (the plugin), NOT persona-engine.** This mission file lives
in persona-engine only because that is where the lead dispatches from. Branch only — no commit to
main, no push, no merge; the lead does that.

Founder order 2026-08-04: fix this now, it is important. Three lanes died this way today.

## The defect, with today's evidence

Lane `b0370efc` (menubar mission). Journal, verbatim:

```
15:37:40 arm_resolved job=build arm=glm
15:37:40 candidate_chain task=b0370efc arms=glm,sonnet
15:37:41 worker_spawned by=router model=glm  handle=260804-183741-b0370efc-0026
15:43:42 e2e_gate task=b0370efc status=ran verdict=fail rc=1
15:43:44 dispatch_terminal task=b0370efc terminal=dead cause=e2e_regression
```

GLM wrote **nothing**: the lane worktree was byte-clean and
`docs/handoff/dispatch-b0370efc/` contained **no `developer.stream.jsonl` at all** (a healthy
lane's is megabytes — compare `dispatch-c91e8cca`). Sonnet, the declared second link of the
chain, was never spawned. Same shape earlier today with a quota-locked codex (lane `81ec9717`).

## Why the chain does not advance (established — do not re-derive)

`leadv2-dispatch-code.sh:2643-2705`: the candidate loop advances only on `arc=7`, a refusal at
**spawn** time. On `arc=0` the spawn is confirmed and the dispatcher `exit 0`s immediately — the
worker is asynchronous. "The arm produced nothing" happens minutes AFTER the dispatcher is gone,
so no process is left holding the chain. `LEADV2_LANE_SILENT_MAX_S` exists but is only consumed
by `leadv2-lane-liveness.sh:62` via `leadv2-supervise-loop.sh:100`, and **supervise is PAUSED**
(founder order 2026-08-02), so in single-lead mode nothing watches.

The stream path is already known to the code: `leadv2-dispatch-code.sh:953` builds
`${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/developer.stream.jsonl`.

## Required

Two separable fixes. **Both are needed; do not stop after the first.**

1. **A silent arm must not be labelled a regression.** In
   `leadv2-dispatch-product-close.sh`, before the e2e gate runs, check whether the arm produced
   anything at all — no stream file, or a stream file with zero assistant events, AND a lane
   worktree with no changes. If so, skip the e2e gate entirely and retire the lane with a
   terminal that says what actually happened (an `arm_produced_nothing` cause under the existing
   `no_work` / retryable terminal vocabulary — see `leadv2-dispatch-ledger.sh`; do NOT invent a
   new terminal word). A byte-clean lane cannot have regressed anything, and `dead` is
   write-once, so a wrong `dead` permanently poisons the row.

2. **The lane must actually advance to the next arm.** Give the close gate — the one process
   still alive and already watching the lane — the ability to detect the silent-arm case and hand
   the mission to the next candidate rather than ending the lane. The chain is already journalled
   (`candidate_chain task=<sig8> arms=glm,sonnet`), so the next arm is recoverable from the
   journal; if you would rather thread it explicitly, do that and say so in your deliverable.
   Re-dispatch must be **one-shot per arm** (never a loop that can retry the same silent arm
   forever) and must not fire when the worker is merely slow: a stream file that exists and is
   growing is a working arm, however quiet the journal is.

If you conclude fix 2 cannot live in the close gate, say so explicitly and implement the smallest
thing that DOES advance the chain — a correct label with no advance is only half the order.

## Rules

- **bash 3.2.** No `declare -A`, no `${var^^}`, no `mapfile`, no `<<<`. The file's own comments
  at :2637 explain why.
- The plugin's scripts are symlinked into persona-engine, m3-market and respiro-ios — a
  regression here breaks dispatch in all three.
- Do not weaken any existing gate or fixture to get green.
- Do not touch `~/.claude/leadv2-shared/` or any project's `.claude/leadv2/`.
- `.env` READS only.

## Done means

- A test proving a lane with NO stream file and a clean worktree retires with the
  arm-produced-nothing cause and **never** reaches the e2e gate.
- A test proving a lane with a real stream file and real work is completely unaffected — same
  verdict as today.
- A test proving a slow-but-working arm (stream file present, worktree still clean) is NOT
  treated as silent.
- A test proving the chain advances exactly once for a silent arm, and that a second silence on
  the same arm does not re-dispatch it again.
- `bash -n` clean on every file touched, and `/bin/bash` (3.2) `-n` too.
- Run the product-close and dispatch-ledger suites and paste them in full. **Do NOT run
  `run-core-offline.sh`** — it takes ~10 minutes and has already eaten one worker's entire budget
  today.
