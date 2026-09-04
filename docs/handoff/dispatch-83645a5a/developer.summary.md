verdict: APPROVE
next_action: continue

Added a third "finished" liveness state to `leadv2-lane-liveness.sh` and `leadv2-lanes-snapshot.sh`: no live pid + a commit in the lane's own worktree within 1800s, checked before any freshness logic.

- Finished lanes no longer escalate (dead-candidate veto) and no longer block re-dispatch (`alive`/`starting:*` check in dispatch is downstream of the liveness verdict).
- `test-lane-finished-state.sh`: 6/6 pass, incl. 2 in-place mutation RED/GREEN gates on the real production files (no scratch copies).
- Branch lineage note: `7f22d3d` (worker_pid fix) is not an ancestor of this lane's HEAD, so its regression test doesn't exist here — `leadv2-active-registry.sh` is untouched, confirmed via `git diff --stat`.

Full: developer.full.md
