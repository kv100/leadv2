verdict: APPROVE
next_action: continue

DECISION: option a — ship helper + fixture-proven pattern this lane; convert the 3 named watchers in a follow-up lane.
- codex-task.sh __quota-watch is quota-gate logic with delicate lockout/cooldown fencing; a mechanical sleep-swap without per-loop fixture proof risks an active regression in the gate, worse than a deferred hygiene fix.
- Expanding LANE_WRITES mid-build for 3 files (11 sleep sites) multiplies review surface on an already fixture-proven deliverable.
- Follow-up lane must carry per-watcher no-orphan assertions.

Full: full.md
