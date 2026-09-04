verdict: APPROVE
next_action: continue

DECISION_OPTION: a — wire complexity into the live `route_arbiter()`.

- Verified: arbiter runs at 4 spawn sites in dispatch-code.sh guarded only by `declare -F`; the router-v2/judge chain sits behind its own env gate.
- Option (b) ships dead code and closes the lane with the defect live.
- (a) is additive; rollback via routing.yaml/env. Guardrails + risks in full.

Full: architect.full.md
