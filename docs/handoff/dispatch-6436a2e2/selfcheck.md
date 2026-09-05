# builder selfcheck — dispatch-6436a2e2
generated_at: 2026-09-04T09:59:21Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01
diff_hash: a705057933854d68a0e509d9ba9e5d69f2e78895284d06ae175035c193368dbb
checks: 10   failed: 0   skipped: 1

| check | target | rc |
|-------|--------|----|
| scope | 9 files, write-set honored | 0 |
| bash -n | plugins/leadv2/scripts/claude-subsession.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-active-registry.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-agent-stats.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-backfill-history.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-helpers.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-negative-memory-compile.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-priors-compile.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-rag-intake.sh | 0 |
| bash -n | plugins/leadv2/scripts/leadv2-status-snapshot.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01/tests/run-all.sh | SKIP (delegated_to_e2e) |

verdict: GREEN
