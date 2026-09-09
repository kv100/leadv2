# The lane terminal row (LANE-TERMINAL-ROW)

Founder order, 2026-09-09: three lanes (`G-WORKFLOW-STEP`, `SESSION-START-COST`,
`CONTINUATION-GUARD-DUP`) finished real, mergeable work and died without leaving a
terminal row in their journals. The lead found each one only by going and looking, and
answered `abandon` on lanes whose work was complete — **a finished lane and a crashed
lane were indistinguishable from the outside.** This reference defines the contract that
closes that defect: which process writes the row, on which path, in which vocabulary —
and what deliberately remains uncovered.

## The row

One journal line per lane lifetime, in the lane's own journal
(`leadv2-journal.sh tail dispatch-<sig8>`), written by
`leadv2-dispatch-product-close.sh` — the process that is still alive when the outcome
becomes known:

```
dispatch_terminal task=<sig8> terminal=<state> cause=<cause> [commit=<sha>] [source=exit_trap] [worker_reason="..."]
```

The shape is byte-identical to what the terminal ledger
(`leadv2-dispatch-ledger.sh write-terminal`) has always written on success; the existing
readers (`leadv2-lane-watch.sh`, `leadv2-lane-pulse-watch.sh`, `leadv2-skill-rollup.sh`)
grep `dispatch_terminal task=` and read `terminal=`/`cause=` positionally, so trailing
keys are additive and change no parser.

## Reading the state word — what a human does next

| `terminal=` | means | human action |
|---|---|---|
| `landed` | finished, gates passed, merged-or-mergeable | verify + merge |
| `finished_unlanded` | finished with a deliverable, not landed | review the deliverable |
| `pass_unlanded` | gates passed, durable human-action state | act, do not re-dispatch |
| `dead_with_unlanded_work` | **the close process died, but the worktree carries work** (`commit=` names it) | **salvage — never `abandon`** |
| `dead` | died, nothing salvageable | abandon / re-dispatch |
| `no_work` | ran, produced nothing | re-dispatch after reading `worker_reason` |
| `parked` | deliberately parked | unpick when ready |
| `refused` | pre-verdict refusal (writeset, shape, ...) | fix the cause, new attempt |

`dead` vs `dead_with_unlanded_work` is the distinction the 2026-09-09 lanes were
missing: the row itself must answer "is there work sitting in the worktree?" so nobody
opens the worktree — or answers an escalation blind — to find out.

## Who writes the row, on which path

All paths funnel through `_dl_note` in `leadv2-dispatch-product-close.sh` — the single
funnel every terminal verdict passes through, explicit branches and the EXIT trap's
idempotent retry alike:

1. **Explicit verdicts** (`landed`, `parked`, `refused`, `no_work`, ...): `_dl_note`
   calls `write-terminal` (the ledger journals the row on rc=0) and then
   `_pc_journal_terminal_once` checks the journal directly and appends the row itself
   only if it is missing — presence-check-then-append, never rc-echo, because the
   ledger's own journal append is fail-open. A healthy ledger path is byte-identical to
   pre-2026-09-09 behaviour; a ledger outage (TERMINAL_LEDGER=0, missing binary,
   lock-wait timeout) no longer silences the journal.
2. **TERM / INT / HUP mid-run**: `trap 'exit 143|130|129'` converts the signal to a
   normal exit, the EXIT trap fires, and `_pc_crash_terminal` selects the state —
   `dead_with_unlanded_work` + `commit=<sha>` when the lane worktree carries a commit
   younger than the close process's own start (or dirty bytes, trusted only when the
   real lane-guard lib sourced), plain `dead` otherwise. The dispatcher-supplied lane
   root is captured at process start, before normal-path setup, so an early signal
   cannot erase that evidence by arriving before the later root-resolution step.
3. **Crash** (unbound-variable abort, any unenumerated exit): same EXIT-trap path as 2.
4. **Exactly once**: the ledger is write-once per attempt (dedup rc=2 journals nothing
   new), and `_pc_journal_terminal_once` is once-per-process (`_PC_TERMINAL_JOURNALED`),
   so the trap's retry of an explicit verdict can never append a second row.

Regression coverage: `plugins/leadv2/tests/test-lane-always-leaves-a-terminal-row.sh`
(E2E-KILLRATE-01 negative controls — normal finish, TERM/INT/HUP, work-present crash,
exactly-once under a healthy ledger), plus the pre-existing
`scripts/tests/test-dispatch-product-close-exit-trap.sh` (ledger-row side).

## What remains uncovered — SIGKILL, said plainly

**SIGKILL cannot be trapped.** If `leadv2-dispatch-product-close.sh` itself is
SIGKILL-ed (a reaped background task, an OOM kill, a `kill -9` sweep), no trap runs and
no row is written by any path above. That is exactly the observed shape of the
2026-09-09 lanes (journals frozen at spawn+1 min, close-owner pid dead).

The existing instruments that can still say something after a SIGKILL:

- **`leadv2-dispatch-ledger.sh sweep`** writes a `dispatch_terminal ... source=sweep`
  `dead` row once it finds the close-owner pidfile dead. Two honest caveats, verified
  2026-09-09: nothing in `plugins/leadv2/hooks/` schedules it automatically (it is a
  CLI verb), and its dead-state probe distinguishes *dirt* (uncommitted bytes), not
  committed work — a SIGKILLed close over a committed lane sweeps as plain `dead`,
  which is the very ambiguity this lane set out to remove.
- **`leadv2-lane-watch-v2.sh`** (ONE-LANE-WATCH-01) is the watcher that cannot itself
  go silently dead: armed per lead-session from SessionStart hooks, self-terminating on
  dead sessions (WATCHER-LEAK-IS-FAKE-LIVENESS-01), it heartbeats stalled lanes to the
  lead. It notices silence; it writes no terminal rows.

Per the founder's direction this lane adds **no fourth watcher**. The residual, for
whoever picks it up: schedule the sweep (cron/hook) and widen its dead-state probe to
committed work — both edits live in `leadv2-dispatch-ledger.sh`, outside this lane's
declared write set (LANE_WRITES: `leadv2-dispatch-product-close.sh`, the suite, this
document).
