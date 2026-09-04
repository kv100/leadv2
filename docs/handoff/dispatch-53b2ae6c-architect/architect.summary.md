verdict: REVISE
next_action: continue

Design done — the named hook is the lesser suspect.

- `leadv2-worktree-cleanup.sh --sweep-dead` runs unattended each SessionStart via `leadv2-stale-sweeper.sh:399`, doing `remove --force` + `branch -D`. That deletes a lane; the hook cannot. Both get the gate.
- Hook's own bug: wipes `docs/` (lines 90-93) before deciding it may remove — the "gutted" shape.
- `leadv2-orphan-monitor-sweep.sh` clean: kills PIDs only. No change.

Full: full.md
