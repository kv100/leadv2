verdict: APPROVE
next_action: continue

Gate `pc_silent_arm_probe` on a new spawn-time record `docs/handoff/dispatch-<sig8>/arm-registered`; no record → probe never fires → C3's `empty_diff` path keeps the clean lane.

- No existing record (journal, reserve ledger, handle) survives to close time readably — create one, fail-closed.
- Delta on `3bffb24`; C3 untouched; twin discriminator case added to both suites.
- Top risk: arm-token vs AUTHOR mismatch — trace, don't assume.

Full: architect.full.md
