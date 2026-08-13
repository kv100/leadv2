# PANEL-MERGE fix round 1 — the refactor now HIDES live lanes, and the parity test is missing

Resume the work already in `.claude/worktrees/b98371eb` (164 insertions / 154 deletions in
`plugins/leadv2/scripts/leadv2-status-surface.sh`). Do not start over — the refactor direction is
right, it regressed behaviour on the way.

## What the lead measured, not what the gate said

The gate wrote `status: fail / reason: e2e_regression`. **Three of those failures are environment,
not code** — `product_close ... author=codex`, `review-sonnet.md does not exist` — codex is
quota-locked until 2026-08-08, so no reviewer exists. Ignore those; they are not yours to fix.

The real problem is in your own suite. `tests/test-status-surface-single-lead.sh` run directly:
**12 passed, 11 FAILED.** The other two suites are green (bash32 15/0, fast-names 12/0).

## The regression, stated plainly

The mission asked you to stop showing lanes that are NOT active. The refactor now also hides lanes
that ARE active. Eleven failures, and the shape repeats:

- `active dispatch expected '🛠 abcdef12 codex 2m', got '⚪ idle'`
- `bogus state filtered expected '🛠 abcdef12 codex 2m', got '⚪ idle'`
- `(g) expected '🛠 CODEX-FOUNDER-TASK-0 codex ...', got '⚪ idle'`
- `(T-name-1) expected 'M1A-FACT-QUALITY-01 · architect'` — got idle
- `(T-multi) expected repo-b lane with repo suffix` — got idle
- `(c) expected '🛠 3: ...', got '🛠 2: TASK-A sonnet 2m'` — undercounts
- `(f) expected 'FEED-SCAN-USABLE-CAN', got 'FEED-SCAN-USABLE…'` — truncation changed shape

This is the founder's original complaint in mirror image. Before: dead lanes shown. Now: live lanes
hidden. Both are the panel lying about what is running; hiding a running lane is arguably worse,
because an operator reads `⚪ idle` and concludes nothing is happening.

**Separate the two conditions in the code and in the tests.** "Not active" means a lane with a
TERMINAL row, or a queued/reserved ledger row with no arm. It does NOT mean "a lane I failed to
classify". An unclassifiable lane must render as a lane with unknown fields, never be dropped —
silence is the one output that is always wrong here.

## The missing deliverable

`tests/test-status-surface-parity.sh` does not exist. It was the actual point of this task: a merge
without it just resets the drift clock. It must assert both renderers produce the SAME
classification for at least 10 lane shapes — live worker with pid; live worker without pid; terminal
`landed`; terminal `dead`; terminal `no_work`; ledger-only `queued`; `reserved`; unreadable repo
ledger; missing model field; name longer than the column.

## Done means

- `test-status-surface-single-lead.sh` back to **23/0**, with any expectation you deliberately
  changed updated in the test AND justified in one line of the report — never by deleting a case.
- `test-status-surface-bash32.sh` 15/0, `test-status-surface-fast-names.sh` 12/0.
- `test-status-surface-parity.sh` exists, >=10 shapes, green.
- The founder's two requirements still hold: no `terminals unreadable` rows at all, and only running
  lanes in the title and body — with the "no running lanes" case rendering one plain line.
- Run the status-surface suites only. Do NOT run `run-core-offline.sh` — its failures are the codex
  lockout and will mislead you.

## Constraints

- No commit, no push. The lead merges.
