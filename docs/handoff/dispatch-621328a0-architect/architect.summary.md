verdict: APPROVE
next_action: continue

# architect — ARM-PRODUCES-NOTHING-01

Both fixes land in the close gate; `no_work`/`arm_produced_nothing` reused, no new terminal word.

- New `pc_silent_arm_probe` after worker-exit, before `pc_scope_diff` — stream + mtime-growth + lane-dirty predicate; e2e unreachable.
- Chain advance via new `dispatch-code advance-arm`; chain + mission threaded through `spawn_product_close`; per-arm marker = one-shot.

Full: architect.full.md
