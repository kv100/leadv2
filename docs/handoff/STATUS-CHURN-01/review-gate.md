arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,kimi=excluded:safety,opus=ok:15,sonnet=author
verified: 0/2 reason=single_arm_pool
status: fail
critical: 0
high: 2
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/lib/leadv2-status-cache.sh:174 — Cache library is wired into ZERO consumers — the diff touches only lib+instrument+test+run-all, so the fix changes no production behavior and the churn it claims to fix persists
- [High] plugins/leadv2/scripts/leadv2-spawn-rate.sh:125 — Live ps sampling is non-functional on macOS: `etimes` keyword not supported and `comm=` shows `bash` not script names, so the acceptance instrument's ps half always reports zero ob…
omitted: low=5
report: docs/handoff/dispatch-STATUS-CHURN-01/review-glm.md
