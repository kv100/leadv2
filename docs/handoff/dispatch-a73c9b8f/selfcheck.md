# builder selfcheck — dispatch-a73c9b8f
generated_at: 2026-08-21T03:04:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a73c9b8f
diff_hash: 5f6507e1e6bbd59b7ea175fc60088ed87ba4a7b49e1e67588995dc607afb29ce
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-stop-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/a73c9b8f/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
