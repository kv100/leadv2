# DISPATCH-CLOSE-GATE-01 — round 4 report

## C4 rollout decision

`LEADV2_REQUIRE_MISSION_WRITESET` now defaults to `0`. The current extractor sweep
has two false positives in five reviewed correct missions (3/5 precision), so enabling
dispatch refusal by default would park valid work. Operators may opt in with
`LEADV2_REQUIRE_MISSION_WRITESET=1` while the extractor is improved and re-swept.
