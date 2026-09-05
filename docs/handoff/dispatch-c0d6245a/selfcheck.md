# builder selfcheck — dispatch-c0d6245a
generated_at: 2026-08-27T00:41:25Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg
diff_hash: 08950e5d5cf246d9d8f94a52ebc5ca8e522a4a859387c0d9e8707856461bc00a
checks: 14   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 9 files, write-set honored | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-continuation-guard.sh | 0 |
| bash -n | plugins/leadv2/hooks/leadv2-promise-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-ledger.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-plugin-sync.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-continuation-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-dispatch-terminal-deregisters-lane.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-plugin-sync-syntax-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/t16hyg/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-continuation-guard.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-dispatch-terminal-deregisters-lane.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-plugin-sync-syntax-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
