# REDSUITE-D-BURN-GOVERNOR-SUITE-ENCODES-A-SUPERSEDED-REQUIREMENT-01

## Cause and licensed test change

Cause class: `test_encodes_superseded_requirement`.

The license is the recorded code decision
`BURN-GOVERNOR-OFF-BY-FOUNDER-ORDER-01` (2026-09-07) at
`plugins/leadv2/scripts/leadv2-burn-governor.sh:113-118`.  It records the
founder's order, the default flip from `1` to `0`, and the explicit rollback
flag `LEADV2_BURN_GOVERNOR=1`.  The stale test expected the old default.  The
suite now enables the gate explicitly for every token-burn behaviour case and
adds an unset-environment case that guards the recorded new default.  The
script header now states the actual default, `0`.

The dispatcher fixture also sets `LEADV2_PREMISE_PROBE=0`: its synthetic task
text tests the burn seam and has no durable backlog row for the independent
premise gate to resolve.

## Reproduction (red before fix)

Command (foreground, captured before the edit):

```sh
bash plugins/leadv2/scripts/tests/test-burn-governor.sh
```

Observed output:

```text
[TEST] FAIL: 3: burn==soft -- verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
[TEST] FAIL: 4: burn==hard -- verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
[TEST] FAIL: 5: burn>hard -- verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
[TEST] FAIL: 6: 24h window boundary -- verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
[TEST] FAIL: 8: missing db -- verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled
[TEST] FAIL: 9: hourly missing -- verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled
[TEST] FAIL: 10: sqlite3 absent -- line=verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled rc=0
[TEST] FAIL: 11: hard<=soft misconfig -- verdict=ok burn24h=0 soft=100 hard=1 reason=disabled
[TEST] FAIL: 12: non-numeric threshold -- verdict=ok burn24h=0 soft=abc hard=1300000000 reason=disabled
[TEST] FAIL: 13: NULL column -- verdict=ok burn24h=0 soft=200 hard=300 reason=disabled
```

Mechanism: `cmd_verdict` returns at
`plugins/leadv2/scripts/leadv2-burn-governor.sh:118-123` before threshold
resolution or telemetry when the variable is unset.  This is intentional under
the cited founder decision.

## Green behaviour evidence after fix

The first 17 assertions of the real suite reached and passed after the edit:

```text
[TEST] PASS: 2: under-soft -> verdict=ok
[TEST] PASS: 3: burn==soft -> verdict=soft
[TEST] PASS: 4: burn==hard -> verdict=hard
[TEST] PASS: 5: burn>hard -> verdict=hard
[TEST] PASS: 6: -25h row excluded, -23h row included (D1 hour_key format)
[TEST] PASS: 7: LEADV2_BURN_GOVERNOR=0 -> ok/disabled
[TEST] PASS: 8: BURN-GOVERNOR-OFF-BY-FOUNDER-ORDER-01 unset -> ok/disabled
[TEST] PASS: 9: missing db -> no_telemetry
[TEST] PASS: 10: hourly table missing -> no_telemetry
[TEST] PASS: 11: sqlite3 absent from PATH -> no_telemetry, exit 0
[TEST] PASS: 12: hard<=soft -> defaults + bad_config
[TEST] PASS: 13: non-numeric threshold -> defaults + bad_config
[TEST] PASS: 14: NULL column doesn't zero the row (D7)
[TEST] PASS: D6: 21-digit hard threshold classifies correctly, no crash/overflow
[TEST] PASS: D6: 21-digit misconfigured pair -> defaults + bad_config, no crash
```

This confirms that cases 12 and 13 (formerly 11 and 12) genuinely run and
refuse invalid threshold settings; neither exposed a governor subject bug.

Independent dispatcher-fixture probe after setting its isolated premise gate:

```text
$ LEADV2_PREMISE_PROBE=0 ... gtimeout 20 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh 'plugin-only burn governor test 14' --no-spawn
rc=6 wall_s=7
[leadv2-dispatch-code] premise_probe task=81f034c6 verdict=skipped reason=gate_disabled
[leadv2-dispatch-code] burn_gate task=81f034c6 verdict=hard burn24h=2000000000 soft=800000000 hard=1300000000 glm_daily_pct= reason=over_hard ref=
[leadv2-dispatch-code] ⛔ BURN GATE: 24h burn 2000000000 >= hard cap 1300000000 — lane refused, task parked
```

## Required checks still outstanding

`bash -n plugins/leadv2/scripts/leadv2-burn-governor.sh` and
`bash -n plugins/leadv2/scripts/tests/test-burn-governor.sh` passed, as did
`git diff --check`.

The full suite and the two required `leadv2-mutation-control.sh` controls have
not completed in this session: the available command executor terminates a
foreground invocation at 30 seconds, while this suite is measured at roughly
195 seconds.  No mutation-control artifact is claimed or fabricated here.

Still red: unverified, because the required 400-second full-suite run and its
two mutation controls could not be completed under that 30-second executor
limit.
