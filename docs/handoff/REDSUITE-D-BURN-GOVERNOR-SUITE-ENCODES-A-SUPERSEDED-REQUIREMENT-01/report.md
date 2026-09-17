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

## Required checks — completed 2026-09-17

`bash -n plugins/leadv2/scripts/leadv2-burn-governor.sh` and
`bash -n plugins/leadv2/scripts/tests/test-burn-governor.sh` passed.

### Two further fixture defects found by the first full-suite run (still in the committed fix)

The 2026-09-15 session could not execute past 30 s, so two defects below the
ten known failures surfaced only now:

1. **Cases 14–18 — `never_reaches_subject` (fixture, not subject).** The
   suite disabled the premise probe with a bare `LEADV2_PREMISE_PROBE=0`
   assignment; the gate runs in the *child* `leadv2-dispatch-code.sh`
   (`_premise_probe_gate`, `leadv2-dispatch-code.sh:8224`), never inherited
   it, and refused rc=8 `backlog_row_not_found` before the burn seam was
   reached. Observed: `rc=8 ... premise_probe verdict=refused
   reason=backlog_row_not_found` on all five cases. Fix: `export` the
   variable in the suite.
2. **Cases 21/26 — stale hardcoded ceiling.** They asserted glm
   `soft=70 hard=80`; the ceiling lives in
   `config/leadv2-quota-ceilings.sh` and is 95 today, so the governor
   answered `soft=85 hard=95`. Same class case 22 already documents
   (SERIAL-SHARD-SIX-REDS-UNTRIAGED-01). Fix: derive the expectation from
   `leadv2_quota_ceiling glm build` exactly as case 22 does.

### Final suite run (green)

Command, foreground, from this lane worktree, 2026-09-17:

```sh
bash plugins/leadv2/scripts/tests/test-burn-governor.sh
```

Result: **rc=0, 36 passed / 0 failed, wall 3m55s** (macOS Darwin 25.6.0,
well under the 400 s acceptance ceiling).

### Negative controls (leadv2-mutation-control.sh artifacts)

Both artifacts under `mutation-control/`, each with `baseline_rc=0` (scratch
baseline green before the mutant lands) and a red line naming the target
assertion:

1. **Behaviour cases** — mutant in `cmd_verdict`'s live path
   (`verdict=soft` → `verdict=hard` at the soft boundary,
   `leadv2-burn-governor.sh:242`): suite red
   (`FAIL: 23: --provider claude over soft -- verdict=hard ...`).
   Artifact `20260917T010249Z-62391.txt`, mode=worker.
2. **Default-off guard (case 8)** — mutant replacing case 8's
   `env -u LEADV2_BURN_GOVERNOR` with `LEADV2_BURN_GOVERNOR=1`: that exact
   case went red
   (`FAIL: 8: BURN-GOVERNOR-OFF-BY-FOUNDER-ORDER-01 default off --
   verdict=hard ... reason=over_hard`). Artifact
   `20260917T011020Z-48475.txt`, mode=worker. The founder decision is
   guarded by a case that fails when the default is silently re-flipped.

## Left red

Nothing. The suite is 36/36 green at the boundary above; both controls
prove red-capability. Platform caveat per lane-rules: this is a macOS-only
green; it says nothing about the Linux population.
