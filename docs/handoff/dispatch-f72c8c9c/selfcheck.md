# builder selfcheck — dispatch-f72c8c9c
generated_at: 2026-08-23T11:42:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2
diff_hash: 4b6356d110f800e35c8c96080f08dce2ba4a6d6e4cfa819ac265782af30243dd
checks: 10   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 9 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/glm-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/kimi-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-backlog-pump.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lanes-snapshot.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-router.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-collector.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
