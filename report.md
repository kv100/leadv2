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

```text
$ bash plugins/leadv2/scripts/tests/test-phase-record-class.sh
PASS: assert class=Strategic rc=0
PASS: plan-for class=Strategic rc=0
PASS: assert class=Bulk rc=0
PASS: plan-for class=Bulk rc=0
PASS: assert Nonsense keeps rc=4 and prior error
PASS: plan-for Nonsense keeps rc=4 and prior error
PASS: YAML override class=Strategic accepted
PASS: YAML override class=Bulk accepted
RESULT: pass=20 fail=0
```

## Mutation control

```text
$ LEADV2_BUILDER_SELFCHECK=0 bash plugins/leadv2/scripts/leadv2-mutation-control.sh --live plugins/leadv2/scripts/tests/test-phase-record-class.sh plugins/leadv2/scripts/leadv2-phase-record.sh 's|local -r classes="Trivial Light Standard Heavy Strategic Bulk"|local -r classes="Trivial Light Standard Heavy Bulk"|' plugins/leadv2/scripts/tests
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-phase-record-class.sh file=plugins/leadv2/scripts/leadv2-phase-record.sh red_line=PASS: assert class=Trivial rc=0 diff_hash=037d6db3f93b74602b96039878d30eb93470ad35240107c17fdd1fc4814e71bb lane_diff_hash=45997e503da4d74d508ca75404ae233735f539acf9be2a5049a363ef7a92cc51 porcelain_clean=yes
```

The committed probe artifact is
`plugins/leadv2/scripts/tests/mutation-control/20260910T094646Z-live-42505.txt`.
