# builder selfcheck — dispatch-b94c3b1c
generated_at: 2026-09-02T13:00:47Z
diff_root: /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FABLE-THINK-TIER-01
diff_hash: d72111cfe77d7eedec17dfe97dadfd9b1a50978a05c13dcc639d204ec2b95fca
checks: 3   failed: 1   skipped: 2

| check | target | rc |
|-------|--------|----|
| scope | - | SKIP (no_write_set_declared) |
| bash -n | plugins/leadv2/scripts/tests/test-workflow-fallback-guard.sh | 0 |
| bash -n | tests/run-all.sh | 0 |
| suites | delegated: bash /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FABLE-THINK-TIER-01/tests/run-all.sh | SKIP (delegated_to_e2e) |
| falsification | plugins/leadv2/scripts/tests/test-workflow-fallback-guard.sh | FAIL (test_failed:rc=1) |

## raw — plugins/leadv2/scripts/tests/test-workflow-fallback-guard.sh (falsification proof) (rc=1)
PASS: leadv2-diverge.js (fixed, R9) — workflow reached its final return (reconciliation) despite the rejected fallback
FAIL: leadv2-diverge.js negative control — HEAD copy already carries the guard (fetched the fixed version, not the defect); re-anchor the control to a pre-fix ref
PASS: leadv2-po-feedback-loop.js (fixed, R9) — workflow reached its final return (reconciliation) despite the rejected fallback
FAIL: leadv2-po-feedback-loop.js (HEAD/pre-fix mutant) — expected 'throws', got: {"ok":true,"result":{"p0":0,"p1":0,"pass":0,"fail":0,"partial":0,"inconclusive":0,"rounds":0,"followups":[],"audit_path":"docs/handoff/selftest-po/po-audit.md","critic_traps":[]},"calls":["think-model-resolve","phase:Audit","audit","critic-traps","audit-opus-fallback","phase:Build","phase:Verify","verify","phase:Iterate","ledger-flush"]}
PASS: leadv2-audit.js (fixed, R9) — workflow reached its final return (reconciliation) despite the rejected fallback
FAIL: leadv2-audit.js negative control — HEAD copy no longer has the bare unguarded fallback return (fetched the fixed version, not the defect); re-anchor the control to a pre-fix ref
PASS=3 FAIL=3

verdict: RED
