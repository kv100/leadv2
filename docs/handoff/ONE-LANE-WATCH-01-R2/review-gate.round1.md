arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,kimi=excluded:safety,opus=ok:20,sonnet=author
verified: 0/1 reason=single_arm_pool
status: fail
critical: 0
high: 1
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/leadv2-lane-watch-v2.sh:237 — _lw_provider_output_age_min counts runner-written top-level files (progress.log/meta.yaml/exit_code/supervisor.log) as WORKER output for glm/freepool/kimi arms, so a hung or killed…
omitted: low=2
report: docs/handoff/dispatch-ONE-LANE-WATCH-01/review-glm.md
