verdict: APPROVE
next_action: review_round_2

Fixed all four red suites genuinely (rc 1→0 each, clean-main-verified, each
with a negative control): stale hooks.json contract assertion, rotted
mutation anchor, missing lane-birth-anchor discount in
`_pc_lane_commits_ahead`, and a stale doubled-handle GLM stub fixture that
was masking the real G3 failure.

Full: developer.full.md
