# builder selfcheck — dispatch-bb1fca05
generated_at: 2026-09-03T17:20:42Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01
diff_hash: ce3990b736954b80ab6d2a0449d57491c4ea78e67520e88329c0c61fa7eb6bcc
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | tests/run-all.sh | 0 |
| bash -n | tests/test-known-red-allowlist-nested-match.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E2E-GATE-CANNOT-SEE-THE-ALLOWLIST-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | tests/test-known-red-allowlist-nested-match.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
