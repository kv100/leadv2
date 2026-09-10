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

## Syntax and changed-scope runner

```text
$ bash -n plugins/leadv2/scripts/leadv2-phase-record.sh
$ bash -n plugins/leadv2/scripts/tests/test-phase-record-class.sh
$ bash -n tests/run-all.sh
$ git diff --check
exit=0

$ timeout 60 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
exit=124

$ timeout 240 bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
exit=124
```

The focused regression and syntax checks are green. The repository wrapper
never reached a suite result within either foreground bound; it is recorded as
a timeout, not claimed as a passing changed-scope run.

## Existing phase-record suite

The pre-existing `test-phase-record.sh` does not create its fixture in this
sandbox: its bare `mktemp -d` resolves to a denied system temp directory (the
same result occurred with `TMPDIR=/tmp`). This is not treated as a product
regression; the new suite uses an explicit permitted fixture path.

```text
$ timeout 120 bash plugins/leadv2/scripts/tests/test-phase-record.sh
mktemp: mkdtemp failed on .../tmp.bV4B6x2nCr: Operation not permitted
mkdir: /src: Operation not permitted
[PORE-RECORD] pass=7 fail=5
exit=1
```

---

# Mission lint brief contract

Added a decision-completeness refusal (`MISSION_NOT_DECISION_COMPLETE`, rc 9)
for briefs without a `Подход`/`Approach`/`Как делать` heading, plus a
non-blocking `MISSION_MUTATION_WITHOUT_BEHAVIOUR` warning. The new suite is
self-registered for `leadv2-mission-lint` changes.

## Evidence: red before the implementation

```text
[TEST] PASS: bash -n: mission linter parses
[TEST] FAIL: no approach heading -> expected rc=9 and named reason; rc=0; out=
[TEST] PASS: adding only an Approach heading -> exit 0
[TEST] FAIL: mutation without behaviour -> expected warning + rc=0; rc=0; out=
decision-complete function mutation anchor not found
[TEST] FAIL: negative control setup: decision-complete function mutation anchor not found
[TEST] ----
[TEST] PASS=2 FAIL=3
```

## Evidence: green target suite

```text
[TEST] PASS: bash -n: mission linter parses
[TEST] PASS: no approach heading -> MISSION_NOT_DECISION_COMPLETE, exit 9
[TEST] PASS: adding only an Approach heading -> exit 0
[TEST] PASS: mutation without behaviour -> warning and exit 0
[TEST] PASS: negative control: removing check A inside its function makes no-approach case red
[TEST] ----
[TEST] PASS=5 FAIL=0
```

## Evidence: leadv2-mutation-control.sh live run

Artifact: `mutation-control/20260910T092927Z-live-50779.txt`.

```text
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-mission-lint-contract.sh file=plugins/leadv2/scripts/leadv2-mission-lint.sh red_line=[TEST] FAIL: no approach heading -> expected rc=9 and named reason; rc=0; out= diff_hash=0e0fab572690db687cd5151ada6700dc7d0644e1fda12f7b31c7c43a70692ca1 lane_diff_hash=9ad931ee6d680de23a0fcda5a324d96972f7b0159baae038047c66af63a8bbd4 porcelain_clean=yes
```

## Evidence: changed-scope runner

```text
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline--Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-f2c4bf8090d0.lock holder=pid=18158 host=UA-K-VLASENKO-LT-2.local since=2026-09-10T09:32:26Z (held by a concurrent run)
[CORE-OFFLINE] FATAL lock_timeout file=/tmp/leadv2-core-offline--Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-f2c4bf8090d0.lock wait_s=60 holder=pid=18158 host=UA-K-VLASENKO-LT-2.local since=2026-09-10T09:32:26Z
```

The runner therefore did not execute any changed-scope suite in this lane;
the direct target suite above is green.
