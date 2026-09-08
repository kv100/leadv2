# builder selfcheck — dispatch-98777feb
generated_at: 2026-09-08T10:10:41Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/3248eff45bb2
diff_hash: 3a079407fb7f6b9fd2ccf07fd6d4950b85d804bd33bdd1858754026c8f67109b
checks: 6   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 3 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-core-offline-scope-changed.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-scope-empty-lane-is-not-a-full-run.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/3248eff45bb2/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-core-offline-scope-changed.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-scope-empty-lane-is-not-a-full-run.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
