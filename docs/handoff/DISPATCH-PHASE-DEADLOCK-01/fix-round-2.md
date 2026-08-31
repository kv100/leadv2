# DISPATCH-PHASE-DEADLOCK-01 — round 2: your suite is green without your fix

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-PHASE-DEADLOCK-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh,tests/run-all.sh,docs/handoff/DISPATCH-PHASE-DEADLOCK-01/

Rebase onto current main first — `COMPLEXITY-ESTIMATOR-IS-OFF-01`, `REVIEW-VERDICT-COUNTER-03` and
`LEAD-WORKER-CHANNEL` all landed after your branch point, and two of them touch
`leadv2-dispatch-code.sh`.

Your work is committed and preserved (`32571fb`) — the lane was killed by the suite lock before it
could commit, and I salvaged it. Round 1 is not being thrown away. But it is not provable yet.

## The measurement

I ran your suite, then reverted your production change and ran it again:

```
$ bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
[PHASE-PRECONDITION-BOOTSTRAP] pass=15 fail=0

$ git checkout main -- plugins/leadv2/scripts/leadv2-phase-record.sh \
                       plugins/leadv2/scripts/leadv2-dispatch-code.sh
$ bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
[PHASE-PRECONDITION-BOOTSTRAP] pass=15 fail=0     <-- rc=0, STILL GREEN
```

**15 assertions, and not one of them notices that the fix is gone.** The suite is green on the
broken code and green on the fixed code, so it says nothing about either. That is the lying-green
disease in its purest form.

## What is almost certainly wrong

A suite that cannot tell fixed from broken is usually testing a copy of the logic rather than the
logic: a local reimplementation of the precondition check, a fixture that pre-creates the very
artifacts the gate looks for, or a helper the test defines itself. Find out which — from a run, not
by reading — and say so in `report.md`.

The suite must drive **the real `leadv2-phase-record.sh` assert path and the real dispatcher
refusal**, faking only the state root and the handoff tree beneath them.

## The bar for round 2

1. **Revert both production files to main ⇒ the suite goes RED**, and the exit code follows. Show
   the run. Nothing else in this round matters if this does not hold.
2. Restore them ⇒ green. Show that run too.
3. `git diff --stat` clean afterwards.
4. State in `report.md` which of the 15 assertions actually exercised production code before your
   change, and which were vacuous. If the honest answer is "most of them", say that.

## Still binding from round 1

Bootstrap admitted on first dispatch; a lane with phase history missing a mandatory phase still
refused; a lead-authored brief admissible as `attested` plan evidence, never `verified`; the
printed remedy must clear the refusal when run.

**One live consequence to fix as part of this:** `test-effort-routing.sh` is RED on main right now
with `FAIL: sonnet argv=<no argv captured> dispatch_out=... missing mandatory phases:
diverge,plan,gate1`. Its fixture dispatch trips exactly this deadlock. Your round is done when that
suite is green on main again — that is a real, externally-visible proof your change works, worth
more than any assertion you write yourself.

## Rules

- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- Never write to the real state root or the real dispatch ledger.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Run with `LEADV2_SUITE_LOCK_DISABLE=1` — the machine-wide suite lock is what killed round 1.
- `git add <file> <file>`, never `git add <dir>`. **Commit before you stop**, even if partial.

## Done means

Reverting the fix turns this suite red, `test-effort-routing.sh` is green on main, and the report
names which round-1 assertions were vacuous.
