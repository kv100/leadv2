# MISSION — PULSE-IS-A-PLUGIN-DUTY-01, fix round 1

Resume the same worktree (`2b6c3f01`). Review: `docs/handoff/dispatch-2b6c3f01/review-gate.md`,
status **fail**, 0 critical, 1 verified high.

## The finding — `plugins/leadv2/scripts/leadv2-broad-status.sh:83`

On failure the script emits READY **without replacing `founder-status.md`**, so the mandated verbatim
relay can publish the previous, healthy status as if it were the current beat. The founder then reads
"everything is fine" produced by a run that failed.

That is the worst failure shape a status duty can have: it does not go silent (which the founder
would notice), it lies with a stale artifact. Fix it so a failed beat either publishes an explicit
degraded status or refuses to signal READY at all — never leaves the last good file in place while
claiming freshness.

Two properties to hold:

1. **A failed beat is visibly failed.** Whatever the relay picks up must say so, with the reason.
2. **Staleness is detectable without trusting the writer.** If the file carries a timestamp, the
   reader must be able to tell "this is from the previous beat" — do not rely on the failing path to
   remember to update it.

## Test

Force the failure path and assert on what the relay would publish — not on the exit code, not on a
log line. A test that only checks READY is emitted is the test that passed while this bug was live.

## Hard constraints
- Never `reset --hard`, `clean`, or `stash` — three live repos share this tree.
- Do not touch `docs/leadv2/open-threads.md`.
- Do not change the pulse's content contract (one lane table + at most 3 lines) — that is settled.

## Deliverable
The fix, the failure-path test, and one line in `docs/handoff/PULSE-IS-A-PLUGIN-DUTY-01/report.md`
stating what the relay publishes when a beat fails. End with DELIVERABLE_COMPLETE.
