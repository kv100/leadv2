verdict: APPROVE
next_action: continue

Single-lead SwiftBar design ready — three mission premises corrected.

- SwiftBar chain never reads the snapshot; surface.sh must gain a snapshot reader for repo_facts.
- State-dir dispatch-ledger.jsonl is terminal-only; "active" = reservation-ledger row with no terminal sig8 match, TTL-bounded.
- `--all` sections appended as 6/7; ordinals 1-5 unchanged.

Full: architect.full.md
