arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=3 source=pool reason=none excluded=codex=author,kimi=excluded:safety,opus=ok:74,sonnet=ok:74
verified: 0/1 reason=single_arm_pool
status: fail
critical: 0
high: 1
medium: 1
low: 1
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/leadv2-review-run.sh:1065 — hack-detect job now aliases the claude reviewer arm's claude-subsession artifacts (same role=critic + same task-id `dispatch-${TASK}-review`) and runs concurrently with it, clobber…
omitted: low=1
report: docs/handoff/dispatch-bootstrap-routing-glm53-verify/review-glm.md
