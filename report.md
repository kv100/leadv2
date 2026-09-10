# Phase-record class validation report

## Actual class casing

`phase-record` receives producer-class casing: `Strategic` and `Bulk`. The
new focused suite proves those exact values pass both `assert` and `plan-for`,
while lowercase `strategic` and `bulk` remain rejected. No case normalization
was introduced.

## Red baseline

```text
BASELINE command=assert --class Strategic rc=4
[leadv2-phase-record.sh] ERROR: assert: invalid class 'Strategic'
BASELINE command=plan-for --class Strategic rc=4
[leadv2-phase-record.sh] ERROR: plan-for: invalid class 'Strategic'
BASELINE command=assert --class Bulk rc=4
[leadv2-phase-record.sh] ERROR: assert: invalid class 'Bulk'
BASELINE command=plan-for --class Bulk rc=4
[leadv2-phase-record.sh] ERROR: plan-for: invalid class 'Bulk'
```

## Green run

Pending focused-suite and mutation-control output after the implementation is
committed; the final mutation-control artifact is stored under
`plugins/leadv2/scripts/tests/mutation-control/`.
