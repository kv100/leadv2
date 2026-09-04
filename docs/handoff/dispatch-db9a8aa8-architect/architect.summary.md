verdict: APPROVE
next_action: continue

Scoped design for all four watch-layer defects, with three mission-text corrections.

- Terminals are written by `leadv2-dispatch-product-close.sh` `_dl_note()`, not dispatch-code.sh — `worker_reason` wires in there + ledger arg 10.
- `leadv2-status-projects.sh` already lists repos; no new registry needed.
- Watcher uses line-count offsets (atomic-replace safe), not byte offsets.

Full: architect.full.md
