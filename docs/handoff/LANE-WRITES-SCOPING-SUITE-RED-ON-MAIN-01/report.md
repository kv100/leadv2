# LANE-WRITES-SCOPING-SUITE-RED-ON-MAIN-01

## Pre-fix RED: unmodified main

Measurement taken 2026-09-15 on macOS from the pinned lane, invoking the
unmodified main-checkout suite by absolute path at a 900-second bound (it
completed before the bound):

```text
Results: 4 passed(red->green), 8 failed, 5 green-pre-fix, 0 could-not-run
red=4 green-pre-fix=5 could-not-run=0
FAIL: C1-glm: post-fix did not pass (rc=1)
FAIL: C1-codex: post-fix did not pass (rc=1)
FAIL: C1-sonnet: post-fix did not pass (rc=1)
FAIL: C2-b: post-fix did not pass (rc=1)
FAIL: C3: post-fix did not pass (rc=1)
FAIL: H5: post-fix did not pass (rc=1)
FAIL: M7: post-fix did not pass (rc=1)
FAIL: L11: post-fix did not pass (rc=1)
```

Boundary: 17 checks ran (four syntax guards and thirteen named cases); eight
failed. Five other cases were explicitly `GREEN-PRE-FIX`, so they are not
counted as evidence of this fix. The full raw transcript is retained at
`/tmp/lane-writes-main-6217107c.log` for this run.

## Classification before suite changes

The first shared cause is `environment_dependent`: every fixture creates its
scratch repository with bare `mktemp -d`, which inherits the host `TMPDIR`.
In this macOS sandbox that value is a protected per-user temporary directory;
`mktemp` returns `Operation not permitted`. The suite suppresses that error in
the fixture path, then reports a subject-looking `rc=1`. Reproduced without
the suppression: `mktemp: mkdtemp failed ... Operation not permitted`, followed
by product-close `selfcheck_failed` rather than the C2-b assertion's subject.

| Check(s) | Cause class | Fixture location | Classification |
| --- | --- | --- | --- |
| C1-glm, C1-codex, C1-sonnet | environment_dependent; then `never_reaches_subject` | `test-lane-writes-scoping.sh:65`, `:139-149` | The unusable inherited `TMPDIR` prevents the repo fixture. Once scratch creation is made explicit, this launcher path also needs the audited premise escape route so dispatch reaches the cwd recorder. |
| C2-b | environment_dependent | `test-lane-writes-scoping.sh:203-225` | Scratch creation failure is hidden by the command redirection and product-close later reports a generic selfcheck refusal. |
| C3 | environment_dependent | `test-lane-writes-scoping.sh:236-257` | Same root/worktree fixture dependency. |
| H5 | environment_dependent | `test-lane-writes-scoping.sh:320-351` | Its direct `mktemp -d` yields an empty fixture root before its partial-diff assertion. |
| M7 | environment_dependent; then `never_reaches_subject` | `test-lane-writes-scoping.sh:387-415` | Scratch creation prevents architect dispatch; with a valid fixture the ad-hoc dispatch needs `--no-probe-yet` before its LANE_WRITES assertion can run. |
| L11 | environment_dependent | `test-lane-writes-scoping.sh:451-477` | Same root/worktree fixture dependency. |

The C1/M7 second-layer classification is based on the premise gate in
`leadv2-dispatch-code.sh:8299-8301`: synthetic task IDs have no backlog row,
so the gate refuses before the asserted worker/diff behavior. The worked
siblings use the audited `--no-probe-yet` route (`62e7a253`,
`test-dispatch-architect-prepass-late-artifact.sh:70` and
`test-dispatch-architect-prepass-orphan-timeout.sh:52`).

## Falsification attempt and result

I tested the only suite-local changes suggested by that classification: an
explicit `/tmp` fixture root (with a fail-loud invalid-root guard), a real red
premise row for C1, and `--no-probe-yet` for M7. The complete rerun retained
the identical boundary and the identical eight failures:

```text
Results: 4 passed(red->green), 8 failed, 5 green-pre-fix, 0 could-not-run
red=4 green-pre-fix=5 could-not-run=0
FAIL: C1-glm: post-fix did not pass (rc=1)
FAIL: C1-codex: post-fix did not pass (rc=1)
FAIL: C1-sonnet: post-fix did not pass (rc=1)
FAIL: C2-b: post-fix did not pass (rc=1)
FAIL: C3: post-fix did not pass (rc=1)
FAIL: H5: post-fix did not pass (rc=1)
FAIL: M7: post-fix did not pass (rc=1)
FAIL: L11: post-fix did not pass (rc=1)
```

That falsifies the proposed suite-only repair. I reverted the experiment: no
assertion was weakened and no production-ish suite change is being claimed as
a fix. The earlier `mktemp` observation is an environment diagnostic, not a
sufficient explanation for these eight verdicts.

The remaining candidates require a new owning row because they are either
real regressions in the off-limits dispatch/product-close paths or a harness
observability defect that cannot be safely distinguished while every subject
invocation is redirected to `/dev/null`:

| Still-red group | Proposed row title |
| --- | --- |
| C1-glm, C1-codex, C1-sonnet | `LANE-WRITES-C1-LAUNCHER-CWD-SUBJECT-TRACE-01` |
| C2-b, C3, H5, L11 | `PRODUCT-CLOSE-LANE-WRITES-ASSERTION-VERDICTS-01` |
| M7 | `DISPATCH-M7-LANE-WRITES-PREMISE-TRACE-01` |

## Self-check

```text
$ bash -n plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh
rc=0
$ bash plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh
rc=1
Results: 4 passed(red->green), 8 failed, 5 green-pre-fix, 0 could-not-run
```

DELIVERABLE_COMPLETE
