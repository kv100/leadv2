verdict: APPROVE
next_action: continue

Design: `--resume-lane`/`--worktree` pin WORK_ROOT before the `ensure` block in leadv2-dispatch-code.sh; validation refuses (exit 5, no ledger row, no spawn) on missing path, foreign repo, or live lane.

- One pin point → worker cwd, close gate, LANE_START_SHA inherit unchanged; no-flag path byte-identical.
- Pin line prepended in `_spawn_worker_body`, downstream of `compute_sig`, so sig8/dedup unaffected.
- New suite test-lane-placement-pin.sh (8 assertions) + run-core-offline registration (27→28).

Full: architect.full.md
