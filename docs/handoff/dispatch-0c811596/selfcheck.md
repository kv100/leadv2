# builder selfcheck — dispatch-0c811596
generated_at: 2026-09-04T14:19:47Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01
diff_hash: ef4f544b2bcfba8a4762eda549bfb18292df7c3eaa68ec5e946530fbb4bc4931
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 4 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/fixtures/guards/scripts-dir/fx-scriptsdir.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-guard-census.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARD-AUDIT-FINDINGS-NEVER-REACHED-THE-CODE-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-guard-census.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-promise-guard-unknown-kind.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
