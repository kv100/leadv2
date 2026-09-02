# WORKER-ENDS-TURN-ON-WAIT-01 — dispatched workers burn a whole round waiting for their own background job

**Class:** Standard. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 by the persona-engine lead.

## Symptom
A dispatched worker backgrounds a long command (usually `tests/run-all.sh --scope changed`) under a
Monitor or a background Bash, then ends its turn with "waiting for the notification". A dispatched
worker has **no next turn** — the session is `claude -p`, so the round is over. The lane looks alive
(the worker "succeeded"), the report is half-written, and the lead pays a full re-dispatch.

Three occurrences on 2026-09-02 alone, all on the sonnet arm:
| lane | turns | how it ended |
|---|---|---|
| WORKER-DOD-GATE-01 round 2 | 43 + 10 + 8 + 3 | four turns each ending "waiting for the monitor" |
| FABLE-THINK-TIER-01 R7 | 58 | "I'll wait for the background job's completion notification" |
| WORKER-MCP-ALL-ARMS-01 R4d | 83 | "Waiting for task bqzcocsj8 to complete before continuing" |

In two of the three the worker had also left its work UNCOMMITTED, so without the lead committing the
lane by hand the round would have been a total loss (see WORKERS-MUST-COMMIT-01).

Aggravating cause, same day: `tests/run-all.sh --scope changed` can take >10 minutes because
`run-core-offline.sh` waits 600s on a stale lock whose holder pid is dead (found by the FABLE R7 judge).
So the worker's instinct to background it is rational — the fix must address both halves.

## Required
1. **The worker preamble must forbid it.** In the dispatched-worker system prompt: never use Monitor,
   never `run_in_background`, never end a turn on a wait. Long commands run in the FOREGROUND with an
   explicit `timeout`; if the timeout hits, say so in the report and continue with what you have.
2. **The epilogue must detect it.** If the worker's last result text matches a wait phrase
   (`waiting for|I'll wait|before continuing|before proceeding`) AND the lane has uncommitted changes or
   no new commits, the epilogue must commit the lane and journal `worker_ended_on_wait task=<id>` so the
   lead sees the real cause instead of `success`.
3. **Kill the underlying stall.** `run-core-offline.sh` must treat a lock whose holder pid is dead as
   free (verify with `kill -0`), instead of blocking for the full 600s.
4. Suite: a fake worker whose final message is a wait phrase must produce a `worker_ended_on_wait`
   journal line and a committed lane; negative control (phrase absent) must not. Prove the EXTRA_SUITE_MAP
   row with `--scope changed`.

## Evidence
`docs/handoff/dispatch-45cb915e/developer.stream.jsonl`, `dispatch-b94c3b1c/developer.stream.jsonl`,
`dispatch-0537dcc5/developer.stream.jsonl` (result rows, `subtype: success`); persona-engine
`docs/leadv2/open-threads.md` entries of 2026-09-02.
