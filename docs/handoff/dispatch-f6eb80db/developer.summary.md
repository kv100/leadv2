verdict: APPROVE
next_action: review_round_2

Fixed `--worktree` re-entry self-refusal (`lane_is_live` on this run's own row).

- `_resolve_pinned_placement` (leadv2-dispatch-code.sh) now compares a
  `pid_source=lead_durable` liveness row's `pid` against this run's own
  `_lv2_durable_pid()`; a match is skipped as self-evidence, never treated
  as proof the lane is live. `leadv2-lane-liveness.sh` untouched — the
  distinction is identity-based in the caller, not a rung-level exclusion,
  so a foreign lead session's own `starting:*` row still refuses (negative
  control, R-b).
- New suite `test-dispatch-reentry-self-race.sh` (registered,
  `# run-all-triggers: leadv2-dispatch-code`): red on pre-fix `HEAD`
  content (R-a fails with the exact `lane_placement_refused ...
  reason=lane_is_live` bug signature), green post-fix, 6/6.
- No regressions: `test-placement-refusal-exits-before-gates.sh` 4/4;
  `test-lane-placement-pin.sh` 16 passed/11 pre-existing failures,
  identical to unmodified `HEAD` baseline (byte-for-byte same failure set).
- `bash -n` clean on both touched files.

Full: full.md. Report: docs/handoff/DISPATCH-REENTRY-SELF-RACE/report.md.
