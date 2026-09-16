# Diverge — lane 424569a7, how to stop the runner leaking its lock flag into suite bodies

Lead-authored on resume. The lane was killed mid-build by the founder stop order of 2026-09-15, so
this records the option set that the fix has to choose from. It is short because the fork is small
and real, not because it was skipped.

## The constraint any option must satisfy
`run-core-offline.sh:179` re-execs itself under `flock` as
`env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash "${BASH_SOURCE[0]}" …`, and the guard at `:170-172` skips the
lock when that variable is set. Two things must remain true after the fix:

1. The **re-exec** must still recognise itself as the locked child, or the runner takes the lock,
   re-execs, takes it again, and recurses.
2. A **suite body** must see the environment it would see outside the runner, or suites that assert
   about the runner keep failing for a reason that has nothing to do with their subject.

Today only (1) holds.

## Option A — unset the flag immediately before invoking each suite body
Smallest diff, at the one place suites are launched. The re-exec keeps its variable untouched, so
(1) is unaffected by construction. Risk: there may be more than one launch site (serial shard and
parallel shard paths), and missing one leaves the defect alive for half the population — so the lane
must enumerate the launch sites and say how many it found, not assume one.

## Option B — carry the "I am the locked child" fact out of the environment entirely
Pass it as an argv sentinel, or write a marker file the child checks. Nothing inherits, so no suite
can ever see it, and the same class of leak cannot recur for a future variable. Larger diff, touches
the re-exec contract, and `CORE_OFFLINE_ORIG_ARGS` is already forwarded on both re-execs — the file
header warns that dropping those arguments is the silent-arg-dropping defect the `--scope` contract
exists to end, so argv changes need care.

## Option C — teach the suite to detect that it is nested and skip
Rejected before the lane starts, and the lane should not revisit it without saying why. It makes the
suite green by not running, which is the outcome `lane-rules.md` forbids; it leaves the leak in place
for every other suite; and it hides a real runner defect behind a test-side workaround.

## Recommendation
**Option A, unless the enumeration of launch sites shows more than a couple** — in which case B is
cheaper to get right once than A is to get right N times. The lane decides on the evidence and states
which it chose and what it counted.

Whichever is chosen, the negative control is already written: `test-core-offline-lock-01.sh` is rc=0
in a clean environment and rc=1 (`pass=1 fail=2`) with `_LV2_CORE_OFFLINE_LOCK_HELD=1` set. After the
fix the second half of that pair must stop reproducing, and the runner must be exercised end to end
once to prove (1) still holds.

## Not part of this fork
Why `test-dod-gate-suite-registration.sh` and `test-shared-sink-test-guard.sh` are red under the
runner is an open question, not an option to choose between. Every isolated condition tried so far
returns them green. The lane investigates and reports; it does not pick an answer here.
