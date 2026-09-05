# builder selfcheck — dispatch-1c3ad9d0
generated_at: 2026-09-05T05:22:20Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2
diff_hash: 504ba9140a2b16c66fe08569b4ae8dac64074aeacf3b9c714087e40c65631fbc
checks: 11   failed: 1   skipped: 3

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| resolve | .state-backup/questions-main | SKIP (unresolved_path) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-mutation-control.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-dod-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-mutation-control-lane-identity.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-report-only-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-dod-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-mutation-control-lane-identity.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-report-only-gate.sh | FAIL (test_failed:rc=1) |
| falsification | plugins/leadv2/scripts/tests/test-worker-dod-gate.sh | ADVISORY (no_falsification_marker) |

## raw — plugins/leadv2/scripts/tests/test-report-only-gate.sh (falsification proof) (rc=1)
[TEST] PASS: bash -n clean (gate scripts + lib)
[TEST] PASS: /bin/bash -n (bash 3.2 syntax) product-close
=== pass 1/2: post-fix (live tree) ===
[TEST] PASS C1-good-report
[TEST] PASS C2-report-missing
[TEST] PASS C3-report-too-thin
[TEST] FAIL C4-diff-lane-golden
[TEST] PASS C5-dead-worker-kind
[TEST] PASS C6a-unknown-kind-gate
[TEST] FAIL C6b-unknown-kind-journal
[TEST] FAIL C6c-guard-exemption
[TEST] PASS C7-symlink-report
[TEST] PASS C8-dest-collision
[TEST] PASS C9-hardlink-report
[TEST] PASS C10-dest-symlink
[TEST] PASS C11-report-plus-code
[TEST] PASS C12-committed-change
[TEST] PASS C13-git-path
[TEST] PASS C14-rename-launder

=== pass 2/2: red-first pre-fix — reds here are EVIDENCE ===
[TEST] pre-fix ref: bb400e9ba9a85743e21d943038f69214997049bb
[TEST] FAIL C1-good-report
[TEST] FAIL C2-report-missing
[TEST] FAIL C3-report-too-thin
[TEST] FAIL C5-dead-worker-kind
[TEST] FAIL C6a-unknown-kind-gate

Results (post-fix, live tree): 13 passed, 3 failed
FAIL: C4-diff-lane-golden
FAIL: C6b-unknown-kind-journal
FAIL: C6c-guard-exemption
red-first: 5/5 post-fix-passing cases RED against pre-fix

[TEST] 2 passed, 0 failed

verdict: RED
