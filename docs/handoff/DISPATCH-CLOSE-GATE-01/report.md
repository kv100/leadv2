# DISPATCH-CLOSE-GATE-01 — round 4 report

## C4 rollout decision

`LEADV2_REQUIRE_MISSION_WRITESET` now defaults to `0`. The current extractor sweep
has two false positives in five reviewed correct missions (3/5 precision), so enabling
dispatch refusal by default would park valid work. Operators may opt in with
`LEADV2_REQUIRE_MISSION_WRITESET=1` while the extractor is improved and re-swept.

## Round 5 closure evidence

- C1: `leadv2-dispatch-code.sh` now resolves `leadv2-lane-child-suffixes.sh`,
  `leadv2-portable-lock.sh`, and its admission-class library locally first and then from
  `LEADV2_CANONICAL_ROOT`; all three sources are file-guarded.
- C3: `test-red-proof-gate.sh` executes the five production terminal-render expressions and
  requires all five rendered notes to contain the `unproven=` downgrade.
- Source census: [unguarded-sources.md](unguarded-sources.md) lists every detected `lib/`
  source and records the out-of-lane baseline. This lane fixed every unguarded production
  source within its write set.
- Mutation controls were executed in the production files and restored: citation exclusion,
  writeset coverage loop, all three mission-writeset call sites, nonzero RED failure count,
  all five rendered close-note suffixes, and the canonical source fallback.
