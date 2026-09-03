# PHASE-GATE-IS-INVERTED-01 report

## Original deadlock diagnosis

`2a293d8` documents the original failure: `cmd_resolve` records `classify`
before its pre-build assertion, while the assertion required `plan` and
`gate1`. At that point the only accepted plan evidence was a machine-produced
prepass/context artifact and the only gate evidence was a gate sentinel. A
new lane therefore could not satisfy the refusal's prerequisites before a
worker existed.

The deadlock is no longer a reason to admit an unplanned lane. The same change
series made a non-empty lead-authored `docs/handoff/<task>/brief.md` valid
attested plan evidence and a recorded non-empty Gate 1 `--reason` valid
attested gate evidence. Those artifacts can be created before dispatch, so a
Standard or Heavy code-writing lane has a viable, checkable pre-spawn path.

## Chosen boundary

There is no bootstrap exemption for Standard or Heavy code-writing dispatches.
The phase checker reads its own store at assertion time; caller-supplied
`--at-bootstrap` is ignored. This preserves pre-build admission for a resumed
lane only when its own store proves `plan` and `gate1`, and refuses a new lane
until those records exist.

## Baseline evidence

Command:

```text
LEADV2_SUITE_LOCK_DISABLE=1 timeout 120 bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
```

Output before this change:

```text
test: 7 assert --at-bootstrap admits the classify-only fresh lane
[PHASE-PRECONDITION-BOOTSTRAP] pass=21 fail=0
BASELINE_RC=0
```

This is insufficient evidence for dispatch safety because it directly invokes
the checker and supplies the flag that production forwards. The new
`test-phase-gate-inversion.sh` invokes `leadv2-dispatch-code.sh` against a
throwaway Git repository and a stub launcher.

## The fix

Two production files, one logical change:

- `leadv2-dispatch-code.sh` — `_phase_precondition_guard` no longer forwards
  `--at-bootstrap`; `cmd_resolve` and `cmd_advance_arm` no longer run the
  pre-classify `is-bootstrap` probe that fed it. The probe was the bug: taken
  before the lane's own `classify` write, it answered "bootstrap" for every
  brand-new lane, and the guard then skipped plan/gate1 for exactly the lanes
  nobody had planned.
- `leadv2-phase-record.sh` — `cmd_assert` still parses `--at-bootstrap` (old
  callers must not die on usage) but decides nothing from it; it journals
  `bootstrap_claim_ignored` instead. The bootstrap fact is derived only from
  the store, at assert time, by the checker. Because dispatch records classify
  before asserting, the zero-record exemption is unreachable on the real
  dispatch path — which is the correct outcome: a fresh Standard/Heavy
  code-writing lane must carry `plan`+`gate1` records before spawn, and the
  lead-authored evidence path (non-empty `brief.md` = plan, recorded Gate-1
  `--reason` = gate1) makes that satisfiable before dispatch. This is the
  answer to Critical 2: no bootstrap exemption survives for Standard/Heavy
  code-writing lanes; the only surviving exemption is the checker's own
  zero-record store probe, which a real dispatch can never reach (its classify
  write precedes the assert).

[Medium] 4 in the same `leadv2-phase-record.sh` change: the store root now
resolves from `LEADV2_PROJECT_ROOT` **or** `PROJECT_ROOT` (the name the script
itself and the dispatcher's sub-invocations use). When both are set and
diverge, a WRITE refuses with exit 4 (never a silent second store), a READ
warns and proceeds on `LEADV2_PROJECT_ROOT`.

## RED / GREEN proof (mutation inside the production body)

Mutation applied to both halves of the bug on the real call path — the guard
honours `caller_bootstrap` again (`_lane_bootstrap=1` instead of the journal
emit) and `cmd_resolve` re-runs the pre-classify probe with
`_phase_precondition_guard` forwarding `--at-bootstrap`:

```text
test: 1 new Standard dispatch without plan/gate1 is refused before spawn
  FAIL: case1: new Standard dispatch should exit 3 (got 0, out=... arm=glm-flash ... cause=worker_spawned)
  FAIL: case1: refused dispatch spawned a worker (glm)
  FAIL: case1: refusal should name plan and gate1 ()
test: 4 caller bootstrap claim cannot override the recorded store
  FAIL: case4a: claim should be ignored, store should win (rc=0 out=)
[PHASE-GATE-INVERSION] pass=9 fail=4
```

That is `faee3fc5` reproduced exactly: unplanned lane admitted, worker
spawned, refusal names nothing. Mutation reverted (shasum-verified
byte-identical to the fixed tree), then:

```text
test: 1 new Standard dispatch without plan/gate1 is refused before spawn
test: 2 approved new Standard dispatch is admitted
test: 3 resumed approved Standard lane is admitted
test: 4 caller bootstrap claim cannot override the recorded store
test: 5 project-root mismatch fails loudly and PROJECT_ROOT alone is honoured

[PHASE-GATE-INVERSION] pass=13 fail=0
RC=0
```

Cases map to the acceptance list 1:1 (case 5 = acceptance 6, root mismatch).

## Suite wiring

`tests/run-all.sh` EXTRA_SUITE_MAP gained
`leadv2-dispatch-code:…/test-phase-gate-inversion.sh` and
`leadv2-phase-record:…/test-phase-gate-inversion.sh`, so `--scope changed`
selects the inversion regression from either changed stem.

## Falsification set

`bash -n` clean on every changed shell file (both production scripts, all four
touched suites, `tests/run-all.sh`). No Python files changed. Changed-scope
runner output is appended below.

## Changed files

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
- `plugins/leadv2/scripts/leadv2-phase-record.sh`
- `plugins/leadv2/scripts/tests/test-phase-gate-inversion.sh` (new)
- `plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh`
- `plugins/leadv2/scripts/tests/test-phase-precondition.sh`
- `plugins/leadv2/scripts/tests/test-effort-routing.sh`
- `tests/run-all.sh`
