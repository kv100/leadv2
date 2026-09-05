# MAIN-CORE-SUITE-RED-01 — run-core-offline is red on canonical main: 16/85 suites fail

Measured 2026-09-01 on canonical main (~/Projects/leadv2):
`bash plugins/leadv2/scripts/tests/run-core-offline.sh` → suites passed=69 failed=16.

Why it matters: every lane's e2e gate that selects run-core-offline inherits these
failures and dies with a FALSE `e2e_regression` — WATCHER-LIFECYCLE-LEAK-01 burned
3 fix-rounds on main's breakage before the lead sized the swamp. Two examples already
diagnosed:
- `test-t13-slice2.sh` case4a: allowed CLI list was missing `mission-writeset-check`
  and `close-gate` (FIXED in lane c6eb430, now on main).
- `test-landed-at-spawn.sh`: 5 fails — expects terminal-ledger rows on refusal, but
  the dispatcher deliberately no longer writes blocking rows on failed spawns
  ("a failed spawn never leaves a blocking ledger row"). Test is stale vs intended
  behavior — verify intent via git log of that change, then align the test.

Task: enumerate the 16 failing suites (run-core-offline prints them), classify each
as (a) stale test vs intended new behavior, (b) real code defect, (c) environment
dependence; fix category (a) tests and (b) code; report (c) separately. Kill rate
discipline: never weaken an assertion to make it green — align only to PROVEN
intended behavior with the originating commit cited. Acceptance: run-core-offline
fully green on main, negative controls still RED.

Secondary (same root): the e2e gate should compare against a MAIN BASELINE so a lane
is judged on its delta, not on inherited breakage — propose (do not implement without
a follow-up decision) a baseline mechanism in run-all.sh.
