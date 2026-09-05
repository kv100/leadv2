# REVIEW-V3-EFFICIENCY-01-R1

Reduce review cost and latency without weakening the evidence gate.

Required behavior:

1. Default fanout is one independent reviewer.
2. Remove always-on Haiku hack detection. Enable an extra security/hack pass only
   for protected/high-risk paths or an explicit flag.
3. Do not launch one verifier LLM per High/Critical finding by default. Verify
   disputed findings only, behind an explicit/risk-based policy.
4. Key review-round state by task and diff hash so a new diff or fresh lane does
   not inherit a previous version's attempts.
5. Allow one exhaustive review. After fixes, run one targeted delta recheck of the
   previous High blockers; do not repeat a full census. Hard-cap this sequence.
6. Ensure product-close does not run a duplicate inline LLM review when the shared
   review engine already produced the terminal gate.
7. Add executable bounded tests for call counts, risk escalation, fresh-diff state,
   targeted recheck and duplicate-review prevention. No real provider calls.

Keep reviewer independence and fail-closed terminal evidence. Do not touch root
skills, runbook, dispatcher provider fallback or Codex hook files. Commit the lane
and leave it clean.

acceptance:
  surface: review_gate
  observable: Ordinary lanes use machine checks plus one reviewer and at most one targeted High recheck; extra reviewers are risk-triggered, and bounded tests prove no duplicate review path.
  authored_at: 2026-08-24T21:20:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh,plugins/leadv2/scripts/leadv2-dispatch-product-close.sh,plugins/leadv2/scripts/tests
