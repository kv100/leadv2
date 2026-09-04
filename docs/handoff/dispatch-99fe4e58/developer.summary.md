verdict: APPROVE
next_action: deploy

Fixed the commits-ahead probe to report "unknown" instead of "0" when no base resolves, and made both suites hermetic — the two reds were env leakage, not product bugs.

- `_pc_lane_commits_ahead` widened to a 3-state channel; caller treats "unknown" as NOT silent, journals `silent_probe_base_unresolved`.
- Both test suites now scrub ambient `LEADV2_*` before running; Case 2 declares an explicit empty write-set; `arm_advance` assertions tightened to `arm_advance task=`.
- All 3 required verifications green (11/11, 12/12, hermeticity proof clean under leaked env). 3 pre-existing run-core-offline.sh failures confirmed unrelated (2 known + 1 fails identically against `git archive HEAD`).

Full: full.md
