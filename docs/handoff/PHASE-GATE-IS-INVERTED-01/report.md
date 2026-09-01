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
