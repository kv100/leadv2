verdict: APPROVE
next_action: continue

Scope the relay at DELIVER in the single-lead-beat hook: new ownership resolver, per-session delivery watermarks, two context shapes (RELAY=full vs one-line RELAY=none), conditional anchor directive.

- Owner = live `.supervise-active` ancestor, else `.pulse-beat-owner`; unresolved → full relay (fail-open).
- CRITICAL: shared `.pulse-delivered` must go per-session or the owner is starved.
- 2 HOOK files → plugin-cache copy + session restart required.

Full: architect.full.md
