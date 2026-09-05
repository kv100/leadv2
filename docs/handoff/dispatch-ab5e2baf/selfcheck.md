# builder selfcheck — dispatch-ab5e2baf
generated_at: 2026-08-29T12:34:52Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27
diff_hash: aaf0508c06c90f9615bf8c88c09c3ddca1d40468296955dddab3ff5d16eb4953
checks: 5   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-phase8-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
