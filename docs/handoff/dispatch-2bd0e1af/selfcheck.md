# builder selfcheck — dispatch-2bd0e1af
generated_at: 2026-08-30T17:09:35Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01
diff_hash: b0dbd8f84ab1ec1bd48fa7ac1200fce6a9451e6679c28795d6d8ed31cc4279d4
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/freepool-coder.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-output-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-output-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
