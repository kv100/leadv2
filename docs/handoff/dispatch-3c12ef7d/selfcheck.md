# builder selfcheck — dispatch-3c12ef7d
generated_at: 2026-09-08T18:13:56Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B5-HANDOFF-WRITESET
diff_hash: a58c62b849979b9a328759829cc848dbccca30f495b67b78dc9014d79b598ac2
checks: 4   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 2 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/tests/test-handoff-only-write-set-is-refused-early.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/B5-HANDOFF-WRITESET/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/tests/test-handoff-only-write-set-is-refused-early.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
