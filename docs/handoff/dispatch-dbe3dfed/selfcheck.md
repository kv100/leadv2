# builder selfcheck — dispatch-dbe3dfed
generated_at: 2026-08-23T12:56:54Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/dbe3dfed
diff_hash: 67cdb073a462c7834c4af7e4433619e54f167491bacbc58338e0becf6c696f5a
checks: 9   failed: 1   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-parked-worker-resume.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/dbe3dfed/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-parked-worker-resume.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-parked-worker-resume.sh (falsification proof) (rc=1)
[TEST] FAIL: contract red-first (pre=0 post=0)
[TEST] PASS: clean waiting result with unsatisfied deliverable classifies parked
[TEST] PASS: parked outcome carries continue next
[TEST] PASS: clean success stream replay is parked-shaped
[TEST] PASS: clean success with deliverable does not resume
[TEST] PASS: parked lane launches exactly one resume
[TEST] PASS: second parked exit does not loop
[TEST] PASS: second parked exit journals already_attempted
[TEST] PASS: positive control died-with-work resume remains green
[TEST] RESULT: pass=8 fail=1

verdict: RED
