arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=1 source=pool reason=none excluded=codex=author,kimi=excluded:safety,opus=unknown,sonnet=unknown
verified: 0/1 reason=single_arm_pool
status: fail
critical: 0
high: 1
medium: 3
low: 5
findings_source: finding_lines
findings:
- [High] docs/handoff/GLM-5.3-ROUTING-FINAL/review.diff:12 — Corrupt patch artifact: `git apply --check` fails (\"error: corrupt patch at line 12\", rc=128) — hunk headers' line counts don't match bodies (e.g. policy-resolve hunk says +4 l…
omitted: low=5
report: docs/handoff/dispatch-GLM-5.3-ROUTING-FINAL/review-glm.md
