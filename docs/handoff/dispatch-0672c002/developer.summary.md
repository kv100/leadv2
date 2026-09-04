verdict: APPROVE
next_action: review_round_2

Brief's named call sites (resolve_arm/resolve_v2_dispatch) are inactive shadow paths; the real live selector is `route_arbiter()` in leadv2-route-arbiter.sh, which never consulted complexity. Fixed there (data-driven `complexity_penalty` rule) plus the two shadow paths' collapse bug. New fixture suite `test-complexity-routing.sh`, 10/10 PASS, mutation-kill proven. See developer.full.md.
