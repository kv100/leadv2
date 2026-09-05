# builder selfcheck — dispatch-0591e643
generated_at: 2026-09-04T17:32:15Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01
diff_hash: e65f864e787f6f7ed192c52d60103e5f6b44057ad5d30e7075ff53197bbd9ecb
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-phase-gate-default-class.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-phase-gate-default-class.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
