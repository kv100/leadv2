# builder selfcheck — dispatch-6321b955
generated_at: 2026-08-24T13:40:16Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8e705910
diff_hash: 63bb8f2ef8b6abad3c144db1af215f9178ca383c7deb97a1ab6c852479d59323
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-fanout.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8e705910/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
