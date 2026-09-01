# PHASE-GATE-IS-INVERTED-01 — the phase gate waves through new lanes and blocks resumed ones

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-IS-INVERTED-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh,plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh,plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh,tests/run-all.sh,docs/handoff/PHASE-GATE-IS-INVERTED-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## The founder's question, and the measurement that answers it

> "я уверен что задачи идут не через 9 фаз а абы как, так что прошлые фиксы которые должны это
> блокать — не факт что работают"

He is right. Measured on four live lanes, 2026-09-01:

```
a288d3f8  FORK-STORM        classify:done plan:done gate1:done build:running e2e:running
168e6ff1  PLUGIN-PAPERCUTS  classify:done plan:done gate1:done build:running e2e:running
0ea739de  SUITE-LOCK-FD-04  classify:done plan:done gate1:done build:running e2e:running
faee3fc5  MAIN-CORE-RED     classify:done                      build:running
```

`faee3fc5` is running right now, rewriting fifteen core suites on main, **with no `plan` and no
`gate1` record at all**. The three lanes that DO carry both are the ones the lead had to record by
hand, because the same guard refused them three times each.

## The mechanism

`DISPATCH-PHASE-DEADLOCK-01` admits a lane with zero phase records as "at bootstrap". Its own
comment claims the exemption closes immediately:

> "The instant any phase record exists for the lane (typically `classify`, written by dispatch-code
> immediately before it calls the guard), bootstrap is over ... Do not read this as 'phases are now
> optional' — a Standard/Heavy lane that genuinely skipped planning after classify was recorded is
> still refused."

That protection does not hold, because `leadv2-dispatch-code.sh` probes bootstrap **before** it
writes `classify`, and then forwards its own stale answer to the guard:

```
[[ "${_lane_at_bootstrap:-0}" == "1" ]] && assert_args+=(--at-bootstrap)
```

So for a brand-new lane the answer is always "yes, at bootstrap", `classify` lands a moment later,
and the guard is told to skip the check anyway. The comment describes a protection the code
forwards its way around.

**The result is exactly inverted.** A new lane — the one nobody has planned, scoped or approved —
is admitted unconditionally. A resumed lane, which already has records and already did work, is the
only kind the gate ever stops.

## [Critical] 1 — decide the bootstrap answer where the check happens

The guard must determine bootstrap state itself, from the store, at the moment it asserts — not
accept a caller's claim about it. A caller-supplied `--at-bootstrap` is an assertion by the party
being checked, which is not a check at all.

If the deadlock that `--at-bootstrap` was added to solve is real, solve it a way that does not put
the answer in the caller's hands. Diagnose the original deadlock from the runtime and describe it in
`report.md` before you change the mechanism — do not delete the flag blind and re-create the
deadlock.

## [Critical] 2 — the exemption must be narrower than "any new lane"

Whatever survives, a Standard or Heavy lane that will write production code must carry `plan` and
`gate1` before a worker is spawned. If bootstrap must exist at all, bound it: to a specific class, to
a lane whose write set is `tests/` and `docs/` only, or to an explicit one-shot waiver that is
journaled. Say which you chose and why.

## [Critical] 3 — the existing suite passes while this is broken

`test-phase-precondition-bootstrap.sh` has an acceptance criterion 5 that claims a lane which
"genuinely skipped planning after classify was recorded is still refused". It is green, and
`faee3fc5` shipped past the guard anyway. So criterion 5 tests the guard in isolation with a
correctly-computed bootstrap answer, never the real dispatch path where the answer is forwarded.

Fix the suite so it exercises the guard **through** `leadv2-dispatch-code.sh`, the way production
calls it. A test that cannot see this bug is the reason it survived.

## [Medium] 4 — the second reason the lead could not record a phase by hand

Recording plan/gate1 by hand failed three times before it worked, because
`leadv2-phase-record.sh` resolves its store from `LEADV2_PROJECT_ROOT` while the operator was
setting `PROJECT_ROOT` (the name used inside the script itself, and the name the dispatcher's own
sub-invocations use). The records landed in a different store each time, and `show` reported them
`done` while the dispatcher still saw them missing — a silent divergence with no error.

Make the two agree, or make the mismatch loud. A recorded-and-invisible phase is the same lying-green
shape as everything else in this backlog.

## Acceptance

Fixture-based, never the real phase store:

1. a brand-new Standard lane with no plan/gate1 ⇒ dispatch REFUSED (this is `faee3fc5` today, and it
   must go red before the fix);
2. the same lane after plan+gate1 are recorded ⇒ admitted;
3. a resumed lane carrying plan+gate1 ⇒ admitted (regression guard — this is what broke FORK-STORM);
4. a caller passing `--at-bootstrap` for a lane that has records ⇒ the claim is ignored, the store
   wins;
5. whatever bootstrap exemption survives ⇒ exercised through the real dispatch entry point, not the
   guard in isolation;
6. a phase recorded against a store the dispatcher does not read ⇒ loud failure, never a silent
   `done`.

Add the `EXTRA_SUITE_MAP` row and prove selection with `--scope changed`.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`. Restoring the forwarded `--at-bootstrap` must turn case 1 red.
- A kill counts only if this suite alone goes red, and only if the suite was green first.
- Do NOT weaken any other phase requirement to make this pass.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.

## Done means

A lane that has not been planned and gated cannot spawn a worker, a resumed lane that has been is not
blocked, the bootstrap answer is computed by the checker rather than supplied by the checked, and the
suite fails if any of that regresses.
