# builder selfcheck — dispatch-f3237235
generated_at: 2026-09-08T17:16:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-ALWAYS-UP
diff_hash: d28e5a9ca262fce3842290c8659558e6bd41f4d01de4ce498e1af9df1e2df30e
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/tests/test-a-dead-codex-job-does-not-park-the-provider.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODEX-ALWAYS-UP/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-a-dead-codex-job-does-not-park-the-provider.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
