verdict: REVISE
next_action: continue

Design closed against the code, not the mission's guess: tests + journal line are already in cc938f4.

- `test-worktree-lane-safety.sh` is NOT in `run-core-offline.sh` SUITE_DEFS — it never runs.
- Merge hazard: main's `LEADV2_SWEEP_MIN_AGE_S` vs lane's `_H`; the `_H=0` suites go red.
- Orphan-monitor: safe, different kill-class (pgroups, no worktrees) — audit note only.

Full: architect.full.md
