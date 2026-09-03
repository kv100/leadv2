# MERGE-UP-PHASE8-GATES-01 — report

Two-way merge UP of the 08-17 CLOSE-GATE-BYPASSABLE-BY-ENV-01 hardening from the
repo-farm copies into canonical `plugins/leadv2/scripts/`, then symlinked the
farm copies (`../../plugins/leadv2/scripts/<file>`, the farm's relative style).
Post-port canonical is byte-identical to the farm copies (`diff` clean, rc=0);
canonical's newer fixes (GATE-WRONG-ROOT-FALSE-DEAD-01, GATE-FOREIGN-FAILURE-01,
6be3635) preserved.

Ported: A7 fails closed on a bypassed sentinel with no `bypass_reason`
(assert.sh); PE_SKIP_TESTS detected-and-ignored, reason-mandatory
`LEADV2_E2E_GATE_BYPASS`/`_REASON`, `bypass_reason:` field in all success
sentinels (e2e-gate.sh).

## Suite tails (raw)

```
test-e2e-gate-arch-01:      [TEST] 1 passed, 0 failed                     rc=0
test-e2e-gate-lane-root:    [TEST] 13 passed, 0 failed, 0 not run        rc=0
test-...assert-a2-schema:   === Results: PASS=12 FAIL=0 ===              rc=0
test-e2e-gate-bypass-hardening (NEW):
                            === Results: PASS=6 FAIL=0 ===               rc=0
NEGATIVE CONTROL (L1 hunk reverted in scratch copy, RUN red):
  FAIL: Test 1 (L1): expected rc=0 + bypassed: false, got rc=0 flag=<…bypassed: true…>
  === Results: PASS=5 FAIL=1 ===                                          rc=1
bash -n (assert.sh, e2e-gate.sh, new suite): OK
```

## Honest reds — pre-existing, reproduced at HEAD~1 (pre-port)

- `test-e2e-foreign-failure.sh` rc=1: fixture pins diff root via
  `LEADV2_REVIEW_DIFF_CROSS_REPO=0`, but product-close:1915-1931 no longer
  gates scoping by it → `no_work/empty_diff`. Identical at HEAD~1.
- `tests/run-all.sh --scope changed`: 3 passed, 1 failed (run-core-offline
  aggregate): LANE-PLACEMENT-01 passed=20 failed=5; test-lane-diff-single-repo
  FAIL C5-registered-arm-silent. Both reproduce identically at HEAD~1.

Commit: lane branch `worktree-1c68b2ea` (port 3b68919 + this commit).
