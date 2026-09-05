# builder selfcheck — dispatch-aec141b8
generated_at: 2026-09-02T20:30:40Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/NUDGE-TAX-01
diff_hash: 1ee874102c914a53a362ec540721f677e9ce9445c8b000835ba4ac385582fc79
checks: 7   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/hooks/leadv2-lead-delegation-nudge.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-lead-delegation-nudge.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-loop-detect.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2-loop-detect.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/NUDGE-TAX-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-lead-delegation-nudge.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-loop-detect.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
