arms: glm
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,kimi=excluded:safety,opus=ok:20,sonnet=author
verified: 0/2 reason=single_arm_pool
status: fail
critical: 0
high: 2
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/docs/model-effort-matrix.md:107 — New global invariant \"No think-role spawn site may hardcode an 'opus' literal — call the resolver\" is false in-tree at ≥8 untouched think-role sites (census below); test grep…
- [High] plugins/leadv2/config/model-capability.yaml:38 — Untagged external-system claims (Fable 5.1 GA, 1M context, same Claude Max bucket as Opus) drive code/config decisions (anthropic bucket mapping in glm-policy-resolve.py, context_k…
omitted: low=8
report: docs/handoff/dispatch-FABLE-THINK-TIER-01/review-glm.md
