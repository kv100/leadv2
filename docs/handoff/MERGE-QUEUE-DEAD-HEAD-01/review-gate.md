arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,kimi=excluded:safety,opus=ok:50,sonnet=author
verified: 0/1 reason=single_arm_pool
status: fail
critical: 0
high: 1
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] docs/handoff/MERGE-QUEUE-DEAD-HEAD-01/report.md:95 — Report claims run-core-offline (83 suites) \"includes test-merge-queue-dead-head.sh\" — false: the suite is absent from run-core-offline.sh SUITE_DEFS (grep 'dead-head' → no hi…
omitted: low=5
report: docs/handoff/dispatch-MERGE-QUEUE-DEAD-HEAD-01/review-glm.md
