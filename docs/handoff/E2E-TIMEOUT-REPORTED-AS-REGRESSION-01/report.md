# E2E-TIMEOUT-REPORTED-AS-REGRESSION-01 report

## Decision: timeout handling

The lane is parked with `status: unknown`, `reason: e2e_timeout`, and the timeout
recorded in the journal. It is not marked green because the sweep did not finish,
and it is not marked dead because a timeout is not evidence that the lane changed
code incorrectly. The stop-gate checkpoint runs before the e2e gate, so the lane's
work remains committed for a human to resume or rerun with a suitable budget.

Implementation locations:

- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2697-2722` maps `rc=124`
  to `parked/e2e_timeout`, writes `status: unknown`, and exits 5.
- `plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh:254-265` performs the same
  timeout classification before ownership/foreign-failure classification and
  writes no pass sentinel.
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:2571` invokes the
  stop-gate checkpoint before the e2e stage.

## One-line sweep diagnosis

The sweep timed out because the e2e gate runs the full repository
`tests/run-all.sh --scope changed` fan-in inside the lane; that is too broad to
serve as a semantic per-lane budget, so raising the timeout alone would hide the
scope problem. The correct timeout result is recorded unknown/parked for human
decision.

## Negative control, both directions

The production suite is `plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh`.
It drives the real product-close gate. The mutation claim below is backed by the
production mutation-control artifact, not by this prose:

`docs/handoff/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/mutation-control/*.txt`

### Red output from the intentional mutant

The timeout predicate was temporarily mutated from `124` to `125`; the source
was restored immediately after this run.

```text
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] FAIL: R1: expected exit 5 + status:unknown + reason:e2e_timeout, got rc=8 md=<status: fail
reason: e2e_regression
rc: 124>
[TEST] FAIL: R1: journal missing verdict=timeout line -- $*
$*
$*
$*
[TEST] FAIL: R1: ledger call did not record parked/e2e_timeout -- $*
$*
$*
[TEST] PASS: R1: worker's write survives as a checkpoint commit despite the timeout terminal
[TEST] PASS: R2 (negative control): a real rc=1 failure still classifies as e2e_regression, exit 8
[TEST] FAIL: R2: ledger call did not record dead/e2e_regression -- $*
$*
$*
$*

[TEST] 3 passed, 4 failed, 0 not run
MUTATION_SUITE_RC=1
```

### Green output after restoring the fix

```text
[TEST] PASS: bash -n clean (leadv2-dispatch-product-close.sh)
[TEST] PASS: R1: rc=124 classifies as status:unknown reason:e2e_timeout, exit 5 (not 8/e2e_regression)
[TEST] PASS: R1: journal records verdict=timeout rc=124
[TEST] PASS: R1: ledger terminal is parked/e2e_timeout, not dead/e2e_regression
[TEST] PASS: R1: worker's write survives as a checkpoint commit despite the timeout terminal
[TEST] PASS: R2 (negative control): a real rc=1 failure still classifies as e2e_regression, exit 8
[TEST] PASS: R2: ledger terminal is still dead/e2e_regression for a genuine failure
[TEST] PASS: R3: standalone phase-8 gate records timeout as unknown and writes no pass sentinel
[TEST] PASS: R3: standalone phase-8 journal records verdict=timeout rc=124

[TEST] 9 passed, 0 failed, 0 not run
GREEN_SUITE_RC=0
```

## Platform evidence

macOS targeted suite: exit code `0` (`GREEN_SUITE_RC=0`). Linux container
(`python:3.12`, `timeout 120`): exit code `0` (`linux_container_suite_rc=0`),
with the same 9-pass output.

The explicit shell/Python falsification set was also green:

```text
bash_n_all_rc=0
python_changed_files=none
py_compile_rc=0
```

## Changed-scope selection evidence

The repository changed-scope selector selected the new suite and exited 0:

```text
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-TIMEOUT-REPORTED-AS-REGRESSION-01/plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
run-all: 5 selected, scope=changed, select_only=1
selection_runner_rc=0
```

The suite is registered in `tests/run-all.sh` under both changed production
carriers: `leadv2-dispatch-product-close.sh` and
`leadv2-phase8-e2e-gate.sh`.

## Preservation

The stale branch deletions were restored from `main` for the three named files
and the additionally observed MythicalGames brief, so this lane does not silently
revert unrelated handoff work when merged.
