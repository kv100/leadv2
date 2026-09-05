# builder selfcheck — dispatch-0ea739de
generated_at: 2026-09-01T12:02:43Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-ORPHAN-FD-04
diff_hash: 3d662a79391075b649ceeb092ac5a46ea214dd5d7ae9763478aea605fe731aff
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/SUITE-LOCK-ORPHAN-FD-04/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-suite-lock-scope.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
