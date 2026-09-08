# builder selfcheck — dispatch-75d7ef49
generated_at: 2026-09-08T02:01:14Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/96c2a18e
diff_hash: 0cce439552e5d32967c6b3fb8c6988e64cd7caa67436e448b76f5be5de7c9374
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-task-judge.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/96c2a18e/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-judge-parses-its-own-answer.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
