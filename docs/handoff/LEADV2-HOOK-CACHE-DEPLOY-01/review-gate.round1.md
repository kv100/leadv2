arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,kimi=excluded:safety,opus=ok:49,sonnet=author
verified: 0/2 reason=single_arm_pool
status: fail
critical: 0
high: 2
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] .claude/leadv2-overrides/deploy.sh:5 — Design-cornerstone external claim (\"`claude plugin update` no-ops for a directory-source marketplace when the version string did not change\") carries no inline probe artifact and…
- [High] plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh:6 — Same evidence-free external claim repeated in the sync-script header (\"`claude plugin update` no-ops …\") — census instance #2; the diff's own deliverable never probes it.]}
omitted: low=5
report: docs/handoff/dispatch-LEADV2-HOOK-CACHE-DEPLOY-01/review-glm.md
