# builder selfcheck — dispatch-3d5dd86d
generated_at: 2026-09-02T19:36:36Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-HOOK-IS-A-FORKED-COPY-01
diff_hash: cd7d81405cfc1d820e69d4c5c931731ff61b823489fbbf1cc99e76231236a21b
checks: 3   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-hook-fork-guard.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-hook-fork-guard.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PULSE-HOOK-IS-A-FORKED-COPY-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-hook-fork-guard.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
