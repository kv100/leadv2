arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,kimi=excluded:safety,opus=ok:32,sonnet=author
verified: 0/1 reason=single_arm_pool
status: fail
critical: 0
high: 1
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] docs/leadv2/scheduled-decisions.md:59 — ROLLBACK section still says \"unset LEADV2_PROMISE_GUARD_BLOCK\" reverts to log-only, but this diff changes the hook default to 1 — unsetting is now a no-op and the guard stays b…
omitted: low=3
report: docs/handoff/dispatch-PROMISE-GUARD-TURN-IT-ON-01/review-glm.md
