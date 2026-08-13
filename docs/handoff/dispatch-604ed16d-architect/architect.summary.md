verdict: APPROVE
next_action: continue

# architect — DISPATCH-KIMI-ARM-MISMATCH-01

Design: one shared chain helper + fail-safe unknown arm; kimi out of the resolver spill and the v2 registry.

- Live `arm=kimi` comes from `leadv2-glm-policy-resolve.py` spill, not `router_v2.arms`.
- persona-engine tenant yaml names kimi explicitly — plugin default alone won't stop it; resolver allowlist added.
- Second chain switch at :2777 also carries kimi.

Full: architect.full.md
