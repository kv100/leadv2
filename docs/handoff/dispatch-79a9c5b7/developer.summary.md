verdict: APPROVE
next_action: review_round_2

Arbiter now reads remaining budget + reset time per arm and journals a wait-vs-switch decision; suite green macOS+Linux, negative control proven, `--scope changed` selects it.

- Kept the previous worker's rescued diff (leadv2-route-arbiter.sh window_reset/near_reset_wait, test-quota-reset-arbiter.sh) largely as-is after verifying it end-to-end; fixed one real defect: the rescue commit had bundled off-limits runtime-state file churn (docs/leadv2/*, docs/LEAD_V2_STATE.md) into the lane diff, which I stripped in a follow-up commit.
- Threshold: wait if hours_to_reset <= 10% of the window's own period (5h or 168h), else switch — reproduces both founder examples exactly.
- Missing reset degrades to the window's full period (named default), never zero.

Full: full.md
