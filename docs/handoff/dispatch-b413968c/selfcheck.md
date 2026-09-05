# builder selfcheck — dispatch-b413968c
generated_at: 2026-08-24T10:38:12Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b413968c
diff_hash: 63617a27b5104566187005bda0fc4b49f20867f93eb78da7517326be995f2e47
checks: 17   failed: 0   skipped: 3

| check | target | rc |
|-------|--------|----|
| scope | 16 files, write-set honored | 0 |
| resolve | plugins/leadv2/docs/codex-lead-AGENTS-pilot.md | SKIP (unresolved_path) |
| resolve | plugins/leadv2/docs/codex-lead-pilot-runbook.md | SKIP (unresolved_path) |
| bash -n | plugins/leadv2/config/leadv2-quota-ceilings.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-product-close.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-glm-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-provider-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-review-run.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-review-reroute-note.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/run-core-offline.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-provider-quota-gate.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b413968c/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-burn-governor.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-codex-dead-reroute.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-provider-quota-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
