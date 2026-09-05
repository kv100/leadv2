# builder selfcheck — dispatch-33e16647
generated_at: 2026-09-04T04:22:06Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D6-REGISTRY-LANE-OWNERSHIP-01
diff_hash: 8ec6fd7959e10543a3299d6094ca3276b7cf186816870431f6ec768a10b7de39
checks: 3   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 1 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lead-session-identity.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/D6-REGISTRY-LANE-OWNERSHIP-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lead-session-identity.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
