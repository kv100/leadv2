# builder selfcheck — dispatch-8e705910
generated_at: 2026-08-24T11:28:38Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8e705910
diff_hash: e2559e3414465f5b79d11c3fb392c42c02d0a5c78a2f8a78a59c535fa5c619e3
checks: 8   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 5 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-lane-liveness.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/8e705910/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
