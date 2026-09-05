# builder selfcheck — dispatch-1cba2dfa
generated_at: 2026-09-04T01:11:08Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODE-INTEL-SKIPPED-FIFTEEN-TIMES-01
diff_hash: fd7159a4eeda2bcf17fa7fd2e2aed17ddee22ed026c1395851d65b03fa4bcedc
checks: 6   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-dispatch-code.sh | 0 |
| bash -n | plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CODE-INTEL-SKIPPED-FIFTEEN-TIMES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-leadv2-worker-mcp.sh | ADVISORY (no_falsification_marker) |
| falsification | plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
