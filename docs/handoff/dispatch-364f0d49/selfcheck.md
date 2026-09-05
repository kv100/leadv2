# builder selfcheck — dispatch-364f0d49
generated_at: 2026-08-29T21:01:44Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27
diff_hash: 211608b95829c698552ed7ba8ad3759b58334db488cf9d3f4931ed0428039e40
checks: 3   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/533daa27/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-writeset-admission-block.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
