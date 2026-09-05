# builder selfcheck — dispatch-1c354714
generated_at: 2026-08-30T23:00:01Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01
diff_hash: bc982f828c3d8ddda888e7e3cb715fcaee17acfe40dee503855f84eeb84f7344
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-lib-source-guarded.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lib-source-guarded.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
