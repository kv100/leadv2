verdict: APPROVE
next_action: continue

Design: route v2's `eligible=` through a shared dispatchable filter, arm-id normalization first.

- v2 reads `router_v2.arms` (ids `claude-sonnet`…), v1 reads `router.dispatch_ladder` (`sonnet`) — two registries, no consistency check. CRITICAL.
- Naive filter would empty the v2 chain; normalization mandatory.
- Test 5 has Test 6's exact cwd defect.

Full: architect.full.md
