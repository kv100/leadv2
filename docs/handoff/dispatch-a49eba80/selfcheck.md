# builder selfcheck — dispatch-a49eba80
generated_at: 2026-08-31T14:42:47Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-WORKER-CHANNEL-01
diff_hash: 3619daca53fa03d5706cb74ea91ad98f6a2d74a44ba064e4b654ffb75c62feed
checks: 9   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/ask-lead.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-ask.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-broad-status.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-inbox.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-notify-lead.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lead-worker-channel.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-WORKER-CHANNEL-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lead-worker-channel.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
