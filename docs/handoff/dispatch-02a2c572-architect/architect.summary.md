verdict: APPROVE
next_action: continue

Design scoped: new Stop hook blocks turn-end when docs/tasks.yaml has queued rows and lane-liveness reports count_live=0.

- Fail-open everywhere; own 8-block counter (no reliance on stop_hook_active); registered last in hooks.Stop.
- D1: status set is queued,ready,pending — lib CLAIMABLE contradicts mission's queued|ready.
- D3: dirty-worktree arm deferred to IDLE-LEAD-GUARD-02.

Full: architect.full.md
