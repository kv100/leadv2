# The e2e-gate `fail` on lane `9aed148a` is foreign — paired measurement

Measured by the lead on leadv2 **main**, 2026-09-17, macOS, ceiling 600s.

## The gate verdict

```
2026-09-17T13:17:16Z e2e_gate task=9aed148a status=ran verdict=fail rc=1
```

The failing suite named in `docs/handoff/dispatch-9aed148a/e2e-gate.log`:

```
[CORE-OFFLINE] FAILED: plugins/leadv2/scripts/tests/test-effort-routing.sh (scope-selected ad-hoc)
[TEST] FAIL: P3: expected loud rejection ...; got rc=8, journal: ... premise_probe verdict=refused
       reason=backlog_row_not_found
[TEST] FAIL: P3b: valid tier should resolve cleanly; rc=8
```

## The paired control

```
MAIN test-effort-routing   rc=8   fail_lines=4
```

**Red on main as well**, with the same `rc=8`. `rc=8` is the dispatcher's premise refusal
(`backlog_row_not_found`) — i.e. the suite dispatches with a synthetic task id and is refused
before the mechanism under test ever runs. That is row `7c6299dd7f02`
(`PREMISE-PROBE-REFUSES-EVERY-SYNTHETIC-TEST-TASK-ID-01`), a different row with its own live lane.

**Conclusion: this lane's diff did not cause it.** The gate verdict is a false `e2e_regression` of
the kind `SD-MAIN-CORE-SUITE-RED-01` exists to prevent, and it must not be read as a verdict on
this lane's work.

## What this does NOT license

The same paired measurement was run against the other lane that failed its gate in the same
minutes, `c5db1e4e`, and it came out the **opposite** way:

```
MAIN test-mark-finished-releases-writeset   rc=0   fail_lines=0
```

Green on main, red inside that lane's gate — so there the failure **is** the lane's diff and the
gate was right. Two gate failures minutes apart, one foreign and one genuine. Neither could have
been called without running the suite on main, and asserting "the gate is broken again" would have
been wrong half the time.
