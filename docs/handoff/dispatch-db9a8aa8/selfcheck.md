# builder selfcheck — dispatch-db9a8aa8
generated_at: 2026-08-25T11:47:14Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/db9a8aa8
diff_hash: aa9bbd46131bd298caa7c1c0c5d0eb868028ea8f9829bcabc11455a03a4be20a
checks: 17   failed: 1   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 12 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-watch.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-reason.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-watch-poll.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-prepass-resume-invalidate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/db9a8aa8/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-broad-status-foreign-lanes.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-watch-poll.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-prepass-resume-invalidate.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-worker-reason-terminal.sh (falsification proof) (rc=1)
[TEST] PASS: A1: last result line wins over older assistant text
[TEST] PASS: A2: assistant-text fallback when no result line
[TEST] PASS: A3: 120-char clamp
[TEST] PASS: A4: quote/backslash/newline sanitised (got: He said no and fellnpath C:xy)
[TEST] PASS: A5: codex rollout cwd filter — sibling rollout never wins
[TEST] PASS: A6: glm .out last non-blank line
[TEST] FAIL: A7: empty sources -> empty string (got 'Stopped without closing: the prepass found a census-breaking configuration state before the required gates could run. - ' want '')
[TEST] PASS: A7: empty sources -> rc 0
[TEST] PASS: A8: LEADV2_WORKER_REASON=0 kill switch
[TEST] PASS: B1a: JSON row carries worker_reason
[TEST] PASS: B1b: journal line gains worker_reason token
[TEST] PASS: B2a: empty worker_reason still an always-present JSON key
[TEST] PASS: B2b: journal line has no worker_reason token when empty
[TEST] PASS: B3: cause readback
[TEST] PASS: C1a: no_work terminal journal line carries worker_reason
[TEST] PASS: C1b: review-gate.md gains worker_reason line
[TEST] PASS: C2: no stream source -> no worker_reason token

[worker-reason-terminal] PASS=16 FAIL=1

verdict: RED
