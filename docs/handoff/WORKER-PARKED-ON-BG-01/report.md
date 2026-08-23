# WORKER-PARKED-ON-BG-01 report

## Implemented

- `plugins/leadv2/scripts/leadv2-helpers.sh:67-74` adds the readonly foreground-work contract.
- `plugins/leadv2/scripts/leadv2-dispatch-code.sh:3191-3203` prepends it before the evidence contract, preserving final order: worktree pin, evidence contract, foreground contract, mission. This stays after signature/router work.
- `plugins/leadv2/scripts/lib/leadv2-parked-detect.sh:5-22` is the single bounded (4096-byte) Bash-3.2-compatible phrase detector, with `LEADV2_PARKED_DETECT=0` as the kill switch.
- `plugins/leadv2/scripts/leadv2-lane-outcome.sh:151-179` emits `parked` only for an unbounded clean exit whose final result is parked-shaped and whose declared deliverable is unsatisfied.
- `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:627,1467-1480,1584,2063` accepts `parked` for the existing one-shot resume and labels the clean-exit checkpoint `parked-on-background-job` from either the outcome or the arm-agnostic stream probe.
- `plugins/leadv2/scripts/leadv2-status-surface.sh:874` and `leadv2-lane-class.py:133-134` render a named parked state.
- `plugins/leadv2/scripts/tests/test-parked-worker-resume.sh` is registered at `run-core-offline.sh:267`.

## Verification (raw output)

```
$ bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh
[TEST] PASS: red-first foreground contract reaches glm/kimi/sonnet/codex without changing spawn identity site
[TEST] PASS: clean waiting result with unsatisfied deliverable classifies parked
[TEST] PASS: parked outcome carries continue next
[TEST] PASS: clean success stream replay is parked-shaped
[TEST] PASS: clean success with deliverable does not resume
[TEST] PASS: parked lane launches exactly one resume
[TEST] PASS: second parked exit does not loop
[TEST] PASS: second parked exit journals already_attempted
[TEST] PASS: positive control died-with-work resume remains green
[TEST] RESULT: pass=9 fail=0

$ bash plugins/leadv2/scripts/tests/test-e2e-gate-arch-01.sh
[TEST] PASS: (a) lane-tree testing: worktree fix passes gate (rc=0, e2e-root=worktree)

[TEST] 1 passed, 0 failed

$ bash plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh
review-round-exhaustive: PASS=24 FAIL=0

$ bash -n [all changed shell files] && python3 -m py_compile plugins/leadv2/scripts/leadv2-lane-class.py
$ git diff --check
# both exited 0
```

The required changed-scope runner was run in the foreground:

```
$ bash plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] running 61 suites across 4 shards
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=14 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=9 fail=2 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=13 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=15 fail=0 missing=0
# serial tail completed; aggregate: 59 passed, 2 failed, 0 missing; rc=1
```

The two failures are the declared pre-existing `deferred-GLM ladder (V3-GLM-LADDER-01)` and `fanout classifier/runner guard`; neither was modified.

## Scope / residual

The prepass census matched the live code except for line drift; no unlisted caller or conflicting outcome reader was found. Sonnet/codex remain non-resumable by design: their absent launcher/run-dir mechanism is outside this task. The arm-agnostic checkpoint wording covers their parked stream shape.

## Diff stat

```text
9 implementation/test files changed; plus this report and the new parked-detect library/test files.
```

DELIVERABLE_COMPLETE
