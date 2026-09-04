verdict: NEEDS-INFO
next_action: continue

# dispatch-3dd21396 — E2E-GATE-BROKE-TODAY-01 findings

See worktree report at
`.claude/worktrees/E2E-GATE-BROKE-TODAY-01/report.md` for the full writeup with evidence.

## Summary of findings

1. **Brief premise-2 is wrong**: `tests/run-all.sh:111-115` always adds the full
   `run-core-offline.sh` suite regardless of `--scope`. This is deliberate (comment cites
   `GATE-WRONG-ROOT-FALSE-DEAD-01`), unchanged in the last 24h (checked via `git log` on
   both `tests/run-all.sh` and `plugins/leadv2/scripts/tests/run-core-offline.sh`; suite
   count identical to `main`: 83 `|||bash` rows both places).
2. **Real trigger is host load, not a code regression.** `uptime` showed load averages
   49.11/48.17/44.38 live during this session — consistent with the ~90-row
   `[LEADV2_ACTIVE_OTHER_SESSIONS]` list visible in this very session's context (far more
   concurrent lanes than a normal day).
3. **Structural amplifier**: `run-core-offline.sh` runs 4 parallel shards, then `wait`s,
   then runs 12 `|||SERIAL` suites strictly sequentially (lines 510-567). Total wall time
   = shard time + sum(serial times). Live reproduction this session: the first two serial
   suites (`test-routing-enforcement-p1.sh`, `test-no-work-terminal.sh`) each independently
   exceeded a 60s timeout right now, under today's load. 12 suites × 60s+ alone exceeds
   half the 900s budget before the parallel shards or the other 10 serial suites are
   counted.

## Not done (turn/effort budget — honestly incomplete)

- No live one-file-lane gate run proving in-budget completion (would need either lower
  host load or a serial-tail parallelization fix, neither in scope for the effort spent).
- No fix implemented. Candidate fixes identified but not applied:
  - Parallelize the serial tail (needs a per-suite audit of why each was marked SERIAL —
    some plausibly share sqlite/journal state and must stay serial).
  - Adaptive gate ceiling based on load1/nproc (flagged only — brief forbids raising the
    fixed limit, and this is a variant of that, so left for founder/lead decision).
- No 10-consecutive-runs or mutation-control (baseline_rc/mutated_rc) evidence produced —
  each attempt takes real gate wall time which is currently dominated by host contention
  outside this task's control.

## Boundaries respected

No edits to `main`, `docs/leadv2/`, `tests/known-red-suites.txt`; no assertions weakened;
`EXTRA_SUITE_MAP` untouched. Only `report.md` changed in the worktree.

DELIVERABLE_COMPLETE
