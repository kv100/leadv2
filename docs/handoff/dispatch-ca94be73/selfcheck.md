# builder selfcheck — dispatch-ca94be73
generated_at: 2026-09-04T05:30:07Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01
diff_hash: e7dff702a33874df31f49bfe40767598f56442e175214febdf949e682bdd0264
checks: 3   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-active-register-miss.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LIVE-LANE-IS-ABSENT-FROM-THE-REGISTRY-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-active-register-miss.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
