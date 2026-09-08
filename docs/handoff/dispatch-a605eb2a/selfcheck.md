# builder selfcheck — dispatch-a605eb2a
generated_at: 2026-09-05T23:29:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TESTS-POLLUTE-REAL-JOURNAL-01
diff_hash: 38ba579a8170e58a57348c0b5700f3b248a17d55584db9e65496a11ba5cf762e
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-event.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-shared-sink-test-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/TESTS-POLLUTE-REAL-JOURNAL-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-shared-sink-test-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
