arms: opus
fanout: 1/1 degraded=false launched=1 pool_ok=2 source=pool reason=none excluded=codex=blocked:lockout,glm=author,kimi=excluded:safety,sonnet=ok:15
verified: 0/3 reason=single_arm_pool
status: fail
critical: 0
high: 3
medium: 0
low: 0
findings_source: finding_lines
findings:
- [High] plugins/leadv2/scripts/leadv2-cache-truth.sh:178 — zero denominator prints a fabricated hit_ratio 0.0000 instead of unreported, violating the tool's own missing-is-not-zero invariant (probe: one reported turn with all-zero usage ->…
- [High] plugins/leadv2/scripts/tests/test-cache-truth.sh:236 — mutation controls 2 and 3 print \"control proven red-capable\" when their python assert fires and the mutant was never created (probe: perturbed anchor -> turns='' -> suite still P…
- [High] docs/LEAD_V2_STATE.md:7 — diff carries lead-owned and other-lane runtime files outside LANE_WRITES; applying it deletes 8 live lanes' active-session rows plus rewrites 6 phases.d yamls and 2 task journals]}
omitted: low=6
report: docs/handoff/dispatch-CACHE-TRUTH-01/review-opus.md
