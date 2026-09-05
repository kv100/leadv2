# builder selfcheck — dispatch-c5d8f07c
generated_at: 2026-08-26T23:22:06Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/glm53arm
diff_hash: 906d39833305d00693a960b1dba8ac650fecd52357952ec887fccb59f0ea288f
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-glm-flash-arm.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/glm53arm/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-glm-flash-arm.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
