arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:100,kimi=excluded:safety,opus=ok:39,sonnet=author
verified: 0/1 reason=single_arm_pool
status: fail
critical: 0
high: 1
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] docs/handoff/WORKER-MCP-ALL-ARMS-01/report.md:247 — Deliverable asserts a full `tests/run-all.sh --scope changed` run (\"full run, 2026-09-02, state-file reset beforehand\") but the evidence block is the literal unfilled token `RUNA…
omitted: low=4
report: docs/handoff/dispatch-WORKER-MCP-ALL-ARMS-01/review-glm.md
