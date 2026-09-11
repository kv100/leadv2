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
- [High] docs/handoff/CONTROL-PLANE-REVIEW-01/seed-facts.md:94 — S6 reverts a measured correction and re-asserts the proven-false \"registry is blind / every active.yaml reported 0 lanes\" claim, which drives M4 review missions
- [High] docs/handoff/518b42814626/round1-red.txt:5 — Red artifact contains a SKIP line (\"resolver override is already guard-mutated\") that the committed suite cannot emit — falsification evidence was not regenerated after the fin…
omitted: low=4
report: docs/handoff/dispatch-518b42814626/review-glm.md
