arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=1 source=pool reason=none excluded=codex=author,kimi=excluded:safety,fable=unknown:quota_checked,opus=unknown:quota_checked,sonnet=unknown:quota_checked
unreadable: none
verified: 0/0
status: pass
reviewer: glm
diff: c95e0cfa
findings_source: finding_lines
findings:
- [Medium] plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh:125 — Lib comment still says runner call sites test `if ! leadv2_receipt_is_stale` and records LEAD ACTION \"treat rc 2 as stale, proceed\" — this diff implements the opposite (refuse…
- [Medium] plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh:203 — Case-9 \"propagation\" checks are static greps (`exit \"$receipt_freshness_rc\"` present; count of 3 `elif [[ \"$?\" -eq 2 ]]`), not behavioral: no runner is executed against a rea…
omitted: low=3
report: docs/handoff/dispatch-41d918c32ef0/review-glm.md
