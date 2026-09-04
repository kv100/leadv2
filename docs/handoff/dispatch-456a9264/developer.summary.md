verdict: APPROVE
next_action: review_round_2

Implemented all 4 fixes + T11 test from the mechanism-closed design; both suites green, committed as 27e44a2.

- Locked the .review-round.state read-modify-write (both funcs) with lv2_lock_wait, fail-open on timeout/missing lib.
- Fixed escalation: pointer to use ${HANDOFF} at all 4 sites (2 more than the original mission named).
- Added case 8) arm in dispatch-product-close.sh; removed dead roundcap-limit fallback.
- test-review-roundcap.sh 14/14, test-review-round-exhaustive.sh 24/24.

Full: full.md
