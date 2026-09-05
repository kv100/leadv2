# builder selfcheck — dispatch-fb5b470a
generated_at: 2026-09-04T03:20:31Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REGISTRY-MUST-LEAVE-GIT-01
diff_hash: ad9642ac4634d2b76625007eb0119210974a9b208435a3b7043ee70894c19060
checks: 3   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-state-path.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/REGISTRY-MUST-LEAVE-GIT-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-state-path.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
