verdict: APPROVE
next_action: continue

# architect.summary — MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01

Rebuild `render_single_lead()` on a per-project bundle so reservations and terminals
always come from the same repo; drop terminal lanes; anchor the census regex.

- Ledgers resolved by two different keys (`REPO` vs `STATE_DIR`) → dead lanes look open.
- `--task-id dispatch-<sig8>-architect` matched the worker regex → prepass counted as a lane.
- 4 new tests; SwiftBar header contract frozen.

Full: architect.full.md
