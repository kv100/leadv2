verdict: BLOCK
next_action: review_round_2

Refutation failed — the order-A regression reproduces exactly as described.

- Any ``` fence before `PLAN_YAML:` latches `fence_before_marker`, permanently disabling pass A.
- Order B exits at the prose block's closing fence; legacy pass skipped (a fence exists) → `cat <whole file>`.
- HEAD's awk extracted the YAML correctly on identical input.

VERIFY_VERDICT: upheld

Full: critic.full.md
