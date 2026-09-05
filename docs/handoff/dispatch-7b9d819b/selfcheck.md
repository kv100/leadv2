# builder selfcheck — dispatch-7b9d819b
generated_at: 2026-08-25T00:40:35Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7b9d819b
diff_hash: 172d8399d0e2bb1cd44b2a780d6b3fcfad927a0d4b99600ce60a1c4817562674
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-review-arm-failclosed.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7b9d819b/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-review-arm-failclosed.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
