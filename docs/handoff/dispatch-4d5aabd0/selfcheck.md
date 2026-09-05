# builder selfcheck — dispatch-4d5aabd0
generated_at: 2026-08-23T05:48:31Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/4d5aabd0
diff_hash: 29ed96c32a58dbf4c28c710593626f24d3f84ce25ad13505884b8d037da7f0c1
checks: 11   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 9 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-helpers.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-outcome.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-surface.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-parked-detect.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-parked-worker-resume.sh | 0 |
| py_compile | plugins/leadv2/scripts/leadv2-lane-class.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/4d5aabd0/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-parked-worker-resume.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
