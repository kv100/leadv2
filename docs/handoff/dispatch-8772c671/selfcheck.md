# builder selfcheck — dispatch-8772c671
generated_at: 2026-08-24T12:32:31Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b413968c
diff_hash: 6f2cc2b1d339a94126bedad60dc30ad6642c1a9eb424e65c006551b3f6587007
checks: 11   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 9 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/codex-task.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-burn-governor.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-glm-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-provider-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-provider-quota-gate.sh | 0 |
| py_compile | plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b413968c/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-provider-quota-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
