# SUITE-SPEED-01 — make run-core-offline fast and parallel-safe (~/Projects/leadv2, base 89fe065)

run-core-offline (57 suites) takes 25-40 min and is not parallel-safe: this session measured
~half of every lane's wall-clock in suite runs, 5+ false-red incidents from concurrent runs
(fixture collisions in /tmp + shared repo state), and multiple worker deaths waiting on it.

## Work (in this order; each its own commit)
1. FLOCK: run-core-offline.sh takes an exclusive flock (e.g. /tmp/leadv2-core-offline.lock)
   with LEADV2_SUITE_LOCK_WAIT_S (default: wait, journal a waiting line) — kills cross-run
   false reds immediately. Kill-switch env.
2. HERMETIC: give each suite its own TMPDIR (mktemp -d per suite, exported), and audit the
   worst /tmp-colliding suites (test-stop-gate, test-no-work-terminal, test-report-only-gate
   use fixed-ish fixture paths) — make their fixture roots unique per run.
3. SHARDS: with (2) done, run suites in N parallel shards (LEADV2_SUITE_SHARDS, default
   derived from cores, 1 = today's serial behavior byte-for-byte). Target full run <=10 min.
   Preserve summary line format (`suites passed=N failed=M missing=K`).
4. SLEEP AUDIT: list suites with sleep/poll loops >5s total and replace the top-3 with
   event-file waits where trivial; anything non-trivial goes into the terminal artifact as a
   follow-up list, not a code change.

## Acceptance
Full run green at shards=1 (serial parity) AND shards=N (report both timings) · a deliberate
concurrent second run does NOT produce false reds (flock leg) · red-first legs for flock +
hermetic TMPDIR · bash -n + shellcheck -S warning · COMMIT per item.

## Off_limits
Suite LOGIC/assertions (only fixture roots + runner mechanics); leadv2-dispatch-code.sh;
product-close.sh; supervise*.

## Terminal artifact
Commit shas + serial vs sharded timings + concurrent-run proof + DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-74658fef" "<question>" \
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