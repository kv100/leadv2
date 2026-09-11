arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=1 source=pool reason=none excluded=codex=author,kimi=excluded:safety,fable=unknown:quota_checked,opus=unknown:quota_checked,sonnet=unknown:quota_checked
unreadable: none
verified: 0/2 reason=single_arm_pool
status: fail
critical: 0
high: 2
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/tests/test-stale-receipt-requeue.sh:237 — case9 third arm sets LEADV2_SESSION_PROVIDER=glm which execs leadv2-glm-session-runner.sh at session-runner.sh:111 BEFORE completion_proof_present (:282/:361) — all four changed…
- [High] plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh:128 — rewritten comment claims \"Every runner propagates rc 2\" but the codex path (session-runner.sh:103 exec → leadv2-codex-session-runner.sh:112-131 sentinel_present) honours a stal…
omitted: low=4
report: docs/handoff/dispatch-41d918c32ef0/review-glm.md
