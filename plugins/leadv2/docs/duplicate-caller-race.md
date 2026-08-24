# The duplicate-caller race — dispatch dedup ledger design note

One place that explains why `leadv2-dispatch-code.sh` refuses a second concurrent
caller for the same mission signature (sig8), why the implementation is shaped
the way it is, and which invariants any future change must preserve. The
authoritative narrative lives in the script header (items 1–9 + wave2 round2);
this doc is the readable consolidation, not a second source of truth — on
conflict, the script wins.

## Problem

Two callers (lead session, retry loop, founder relay) can submit the identical
mission string within seconds of each other. Exactly one worker should be
spawned per sig8; the loser must be refused **fast** (rc=2, duplicate) and never
block, poison, or delay the winner — including across the winner's own crash.

## Ledger shape

`dispatch-ledger.jsonl` rows move `pending -> confirmed` (or are removed):

- **Reservation token** = pid + epoch + random — unique per attempt, so two
  same-second callers get DISTINCT rows (a 1-second timestamp is not unique).
- **PENDING_TTL** (default 30s, `LEADV2_DISPATCH_PENDING_TTL_S`): above the
  ~15s worst-case GLM launch. A pending row older than this is stale —
  reclaimed, not deleted.
- **CONFIRMED_TTL** (default 7200s, `LEADV2_DISPATCH_CONFIRMED_TTL_S`): a
  worker's max realistic lifetime. Bounds how long a worker that died before
  confirm/abort can block re-dispatch.
- Stale rows are never proactively GC'd — only exact-token confirm/abort ever
  rewrites a row. Orphan accumulation is an accepted tradeoff.

## Design history (why not the obvious shapes)

1. **Original: permanent reservation.** Three failures: a launch failure left
   the reservation standing (identical retry refused forever); a no-op
   launcher consumed the reservation with an empty handle (silent no-op
   looked like success); `--no-spawn` dry-runs poisoned the ledger for the
   real dispatch that followed.
2. **Fix pass 2: provisional + separate-lock rollback.** Opened the core race:
   caller A reserves+releases, spawn pending; caller B sees A's live-looking
   row and is refused; A's spawn then fails and rolls back — B was refused for
   a task that never dispatched.
3. **Fix pass 3: one flock across reserve->spawn->confirm.** BLOCKED on review,
   for two structural reasons: (a) the lock fd (9) is inherited by the
   DETACHED worker (flock binds to the open file description, not the
   process), holding the per-repo lock for the worker's entire lifetime — the
   next dispatch of ANY sig times out on `flock -w 10`; (b) the launch step
   is not sub-second in practice (GLM quota-read can block ~15s), exceeding
   the lock timeout on its own.
4. **Fix pass 4 (current shape): never hold the lock across spawn.**
   `dispatch_reserve` (short flock, read+append only), `spawn_worker` outside
   any lock with `9>&-` as defense-in-depth, `dispatch_confirm`/
   `dispatch_abort` (short flock) matching the EXACT unique token — never a
   blanket sig filter, so a concurrent caller's in-flight row for the same sig
   is never collaterally deleted. Confirm happens only after a positive
   liveness check (glm: run-dir status; sonnet: `kill -0` on a parsed PID;
   a handle with no PID token is a launch failure).
5. **DISPATCH-OUTCOME-LEDGER-01 (2026-07-29): outcome, not intent.** Incident:
   three lanes dispatched to Codex at 0 credits returned completed/done with
   nothing produced, and their CONFIRMED rows blocked re-dispatch for the full
   2h. Now a CONFIRMED-and-fresh row is resolved before blocking: liveness
   first (alive OR unknown blocks — a live or unprovable task is never freed),
   then, only once dead, an evidence check — a lane-attributed handoff
   artifact or a commit naming sig8 counts; runtime state churn (locks, bus
   offsets, active.yaml) is excluded. Any git/stat failure defaults to
   "evidence exists" (blocks) — the ledger only frees a sig it has POSITIVELY
   proven finished-and-empty. The slow read-only checks run OUTSIDE the lock
   in a first unlocked pass; the re-check under the short flock is pure awk
   excluding only the rows the unlocked pass already proved reclaimable.
6. **DISPATCH-LEDGER-PARTIAL-CLOSE-01: checkpointed != finished.** A lane cut
   off at `--max-turns` commits partial work, which item 5's evidence check
   reads as completed. A dead row is freed when CHECKPOINT.md exists with
   mtime >= created_epoch AND `phase8-passed.flag` does NOT exist (recovered
   lanes fall through to the ordinary evidence check and stay blocked).
7. **STOP-GATE-CHECKPOINT-DEDUP-01 (2026-08-21):** the model-written
   CHECKPOINT.md note is frequently absent, but the MACHINE-written
   `wip(<sig8>): auto-checkpoint on worker exit (STOP-GATE)` commit always
   lands in the lane worktree. That commit (committer `%ct` timestamp >=
   created_epoch, resolved via the lane worktree) is now also accepted as
   cutoff proof. Fails closed on a missing worktree or undateable commit.
8. **wave2 round2 finding 1 (terminal-ledger race):** the duplicate-refusal
   branch used to write a terminal `refused` row for a caller that never ran
   anything. The refusal is fast (lock check) while the winner's `landed`
   write is slow (reserve -> spawn -> confirm), so the loser's "refused" row
   landed FIRST in the write-once terminal ledger and permanently misrecorded
   a successful dispatch as a refusal. Fixed; the regression test is the
   canonical proof.

## Invariants (hard rules for any future edit)

- The flock is NEVER held across a spawn, a liveness check, or an evidence
  check. Nothing slow under the lock, ever.
- Row mutations match the exact unique token; blanket task_sig filters are
  forbidden.
- Fails closed everywhere: unknown liveness blocks, unreadable evidence
  blocks, undateable checkpoint blocks.
- Every carve-out ships with a one-step env rollback (defaults 1 = on).

## Kill switches / knobs

| Knob | Default | Effect |
|------|---------|--------|
| `LEADV2_DISPATCH_PENDING_TTL_S` | 30 | Pending row staleness threshold |
| `LEADV2_DISPATCH_CONFIRMED_TTL_S` | 7200 | Confirmed row staleness threshold |
| `LEADV2_DISPATCH_OUTCOME_LEDGER` | 1 | 0 restores outcome-blind blocking for the full CONFIRMED_TTL |
| `LEADV2_DISPATCH_EVIDENCE_ATTRIBUTION` | 1 | 0 restores the former clock-wide commit check |
| `LEADV2_DISPATCH_CHECKPOINT_CUTOFF` | 1 | 0 disables only the checkpoint carve-out (row falls through to evidence check) |
| `LEADV2_DISPATCH_EVIDENCE_EXCLUDE_RE` | built-in | Runtime-state churn exclusion regex |

`--force` is, by design, never permitted for dedup.

## Regression suites

- `tests/test-dispatch-duplicate-caller-race.sh` — two concurrent sonnet-arm
  callers race the same sig8; asserts exactly one rc=0 / one rc=2, exactly one
  terminal row, and that it says `landed` (not the loser's `refused`).
- `tests/test-leadv2-dispatch-outcome-ledger.sh` — outcome resolution +
  racing-reserves case.
- `tests/test-dispatch-ledger-partial-close.sh` — checkpointed-vs-finished.
- `tests/test-dispatch-retry-dead.sh` — dead-worker re-dispatch.

## Note on mission strings

A mission prefixed `docs-only:` hits the classifier's explicit-mission
fast-path (non-product), so its terminal row is written by dispatch-code.sh
itself immediately on success — which is why the race test (and this lane's
own mission string, `docs-only: duplicate-caller-race <pid> <epoch>`) uses
that exact prefix.
