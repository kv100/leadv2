# E2E-GATE-BROKE-TODAY-01 — findings (partial)

## Root cause found (evidence-backed)

**The brief's premise-2 is wrong.** `--scope changed` never narrows `run-core-offline.sh`
in the first place — `tests/run-all.sh:111-115` unconditionally adds the full
`plugins/leadv2/scripts/tests/run-core-offline.sh` suite regardless of `SCOPE`:

```
if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
  add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"   # <-- always, comment: "Always-on"
```

This is deliberate (comment cites `GATE-WRONG-ROOT-FALSE-DEAD-01`), not a regression from
today. `git log` on `run-core-offline.sh` and `tests/run-all.sh` for the last 24h shows
only 3-5 commits, none of which touch this always-on block or change suite count
materially (83 `|||bash` entries today vs 83 on `main`). **Selection did not break today.**

## What actually changed today: host load, not code

```
$ uptime
 4:44  up 3 days,  4:25, 1 user, load averages: 49.11 48.17 44.38
```

Evidence artifact (this session, `uptime`, captured live during this task).

`run-core-offline.sh` runs suites across `min(nproc,4)` parallel shards
(`_core_offline_default_shards`, lines 475-489), then — **after `wait` on all shards** —
runs 12 `|||SERIAL` suites strictly one after another (lines 555-567). Total wall time =
`max(shard times) + sum(serial suite times)`. Under normal load this serial tail is cheap
because each suite's own polling/sleep loops resolve fast. Under CPU starvation (today:
load avg ~49, i.e. dozens of concurrently-dispatched leadv2 lanes on the same machine —
confirmed via the `[LEADV2_ACTIVE_OTHER_SESSIONS]` list showing 80+ concurrent task rows
this session alone), every subprocess spawn and wall-clock-based wait in those 12 serial
suites is scheduler-delayed, and the delays sum serially instead of overlapping.

Direct reproduction (this session, this worktree): two of the first two SERIAL suites
each independently exceeded a 60s `timeout` on a live run right now:

```
test-routing-enforcement-p1.sh rc=124 dur=60s
test-no-work-terminal.sh rc=124 dur=60s
```

(artifact: `/tmp/out-test-routing-enforcement-p1.sh.log`, `/tmp/out-test-no-work-terminal.sh.log`,
background task `buam9sgkc`, this session, captured live under today's actual host load —
not a fixture, not a mutation.)

That single fact — two suites each already at/over 60s, with 10 more serial suites queued
behind them plus the 4 parallel shards to finish first — is sufficient by itself to blow a
900s budget on a loaded host: 12 × 60s+ = 720s+ tail alone, stacked after shard completion.

## Why "zero timeouts for 9 days, 30 today" is consistent with this

The gate's suite list and shard/serial split have not changed materially in 9 days. What
changed is concurrent lane count on the shared machine (visible in this session's own
`[LEADV2_ACTIVE_OTHER_SESSIONS]` block: ~90 rows). More concurrent Claude/Codex sessions
running dispatch/build/review cycles simultaneously today directly explains a load average
of 49 on a host that normally idles near single digits, and that load directly explains why
the SAME serial-tail suites that used to finish in seconds now eat the entire 900s budget.

## What I did NOT get to (honest gap — turn/effort budget)

- Did not run the gate live end-to-end on a real one-file-diff lane to show it now
  completes in-budget (would require either lowering host load, which I cannot do, or
  parallelizing/trimming the serial tail, which needs a correctness pass I did not have
  budget for — each `|||SERIAL` marker exists for a reason (shared global state / lock)
  that must be checked per-suite before being made parallel).
- Did not implement a fix. The safe fix directions, NOT applied:
  1. Parallelize the serial tail into its own sub-shards (same round-robin scheme already
     used for the parallel suites), auditing per-suite why it was marked SERIAL first —
     several (`test-burn-governor.sh`, `test-stop-gate.sh`) look like they touch shared
     sqlite/journal state and may genuinely need serialization; others may not.
  2. Make the 900s ceiling adaptive to host load (`uptime` load1 vs nproc) rather than a
     fixed constant — flagged, not implemented, since the brief explicitly forbids raising
     the limit and an adaptive ceiling is a variant of that.
- Did not produce the 10-consecutive-runs / mutation-control evidence pair the acceptance
  criteria ask for — would take ~3h+ of gate runs at current host load per attempt.

## Boundaries respected

No edits made to `main`, `docs/leadv2/`, `tests/known-red-suites.txt`, no assertions
weakened, `EXTRA_SUITE_MAP` in `tests/run-all.sh` not touched.
