# builder selfcheck — dispatch-02e9baba
generated_at: 2026-08-20T13:31:31Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/02e9baba
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| bash -n | plugins/leadv2/scripts/leadv2-plugin-sync.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-collector.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-broad-status-duty.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-report-only-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/02e9baba/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
