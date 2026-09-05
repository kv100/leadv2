# builder selfcheck — dispatch-873b0576
generated_at: 2026-09-03T01:57:20Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01
diff_hash: 57b3b11532e197db85b646ea6d6ba59b3756effa534bb17158b9602b56b43739
checks: 4   failed: 0   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/leadv2-proof-lib.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-skill-proof.sh | 0 |
| bash -n | plugins/leadv2/scripts/tests/test-skill-proof-gate.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-skill-proof-gate.sh | ADVISORY (no_falsification_marker) |

verdict: GREEN
