# builder selfcheck — dispatch-ac7b08fc
generated_at: 2026-09-03T20:33:57Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01
diff_hash: 3408ac7882866510402005556fa0ab5d4e82fdb766514582279a78b1d0333f24
checks: 2   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/nc-safety-doctrine-prose-collision.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/nc-safety-doctrine-title-blind.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
