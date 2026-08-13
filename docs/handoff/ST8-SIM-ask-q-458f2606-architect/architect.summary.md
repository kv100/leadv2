verdict: APPROVE
next_action: continue

# ST8-SIM — architect decision

DECISION_OPTION: safe

- Timeout = absence of approval, not consent for an irreversible action.
- `risky|Publish now` is a one-way door: rollback restores state, not effect.
- `safe` costs only latency; publishing stays available next turn.

Full: architect.full.md
