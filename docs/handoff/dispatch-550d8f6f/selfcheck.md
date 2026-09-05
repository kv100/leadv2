# builder selfcheck — dispatch-550d8f6f
generated_at: 2026-09-03T07:57:50Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HANDOFF-DOCS-INVISIBLE-IN-LANES-01
diff_hash: 29bd2e163f47d29d96b87f4de401e3bfa7fe2ff4bd243646bc7678d9203278bb
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/HANDOFF-DOCS-INVISIBLE-IN-LANES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-handoff-docs-not-leaked.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-worktree-base-pick.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
