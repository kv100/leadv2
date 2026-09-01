# MAIN-CORE-SUITE-RED-01 — 15 of 86 core suites are red on main

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/MAIN-CORE-SUITE-RED-01`

LANE_WRITES: plugins/leadv2/scripts/,plugins/leadv2/hooks/,plugins/leadv2/scripts/tests/,tests/run-all.sh,docs/handoff/MAIN-CORE-SUITE-RED-01/

Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured on main, 2026-09-01

`plugins/leadv2/scripts/tests/run-core-offline.sh`, full run (about 12 minutes):

```
suites passed=71 failed=15 missing=0
EXIT=1
```

The runner's own exit code is correct — it is not lying green. The suites are simply red, and they
have been red while lane after lane was accepted against them.

The fifteen:

```
shard 0   landed-at-spawn (no terminal=landed at spawn; target repo keying)
          phase precondition guard matrix                        [PHASE-PRECONDITION] pass=75 fail=4
          claim-evidence gate (CLAIM-EVIDENCE-GATE-01)
shard 1   product-close scopes a single-repo lane worktree
          codex-dead review reroute (QUOTA-GATE-PARITY-01)
shard 2   review round exhaustive/verify-only                    PASS=23 FAIL=1
          deferred-GLM ladder (V3-GLM-LADDER-01)                  FAIL=1
shard 3   review round cap (REVIEW-ROUNDCAP-01)                  PASS=13 FAIL=1
serial    dispatch refusal fallback chain
          product-close waits for worker exit
          Codex full-cycle runner                                PASS=22 FAIL=1
          lanes snapshot reconciliation
          lane truth batch (log_path + quarantine convergence)   pass=15 fail=1
          report-only gate (REPORT-ONLY-GATE-01)
```

Note the serial shard: `pass=7 fail=7`. Half of everything that cannot be parallelised is failing.

## [Critical] 1 — classify before fixing anything

Each of the fifteen is one of three things, and they need opposite treatment:

- **a real regression** — production code broke and the suite is correctly red. Fix the production
  code.
- **a stale assertion** — the contract changed deliberately and the suite was never updated. Update
  the assertion, and state in `report.md` which contract changed and where that decision is recorded.
- **an environment dependency** — the suite needs something this machine does not have (a live Codex
  transport, a quota state, a clock). It must then be made hermetic or explicitly skipped with a
  reason, never left as a permanent red that everyone learns to ignore.

Produce that classification for all fifteen **before** changing a line. A red suite nobody has
classified is how a real regression hides among stale ones.

## [Critical] 2 — a permanent red is worse than no suite

Fifteen standing failures mean the whole run is ignored, which is why nobody noticed. Whatever the
classification, the end state is: the core run is green, or every remaining red is a deliberate,
named, reasoned skip that the runner reports as a skip rather than a failure.

## [Critical] 3 — do not fix a suite by weakening it

The failure mode this repo has hit repeatedly is turning a red suite green by deleting the assertion
that caught the bug. For every suite you make pass, show in `report.md` that it still goes red under
a mutation of the behaviour it covers. A suite that passes and can no longer fail has been destroyed,
not fixed — see `SUITE-THAT-CANNOT-FAIL-01`.

## Scope

Fifteen suites is likely more than one lane. Prioritise in this order and stop when the lane is full,
reporting exactly what is left:

1. `claim-evidence gate`, `report-only gate`, `phase precondition guard matrix` — these gate whether
   a lane's work is accepted at all, so a break here lets unverified work land;
2. `dispatch refusal fallback chain`, `deferred-GLM ladder`, `codex-dead review reroute` — routing;
3. the rest.

## Acceptance

1. all fifteen classified in `report.md` with evidence, before any fix;
2. every suite this lane touches ends green;
3. every suite this lane makes green is shown red under a mutation of its own subject;
4. any suite left red is left red **deliberately**, named in `report.md` with the reason;
5. `run-core-offline.sh` still exits non-zero while any unexplained failure remains.

## Rules

- Mutation INSIDE the production body on the real call path, RED, revert, GREEN, clean
  `git diff --stat`.
- No `grep` against script source as an assertion; no negated command as an assertion; a printed
  `FAIL:` line that leaves `$?` at 0 is not an assertion.
- Never delete an assertion to make a suite pass. If an assertion is wrong, say why in `report.md`.
- Bash 3.2.57 only (no `mapfile`); every `${arr[@]}` guarded under `set -u`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop, even if partial.

## Done means

Main's core run is green, or every remaining red is a named deliberate skip — and no suite was made
green by removing the thing that made it useful.

## Named failures, measured on main 2026-09-01 (not from any lane)

`plugins/leadv2/scripts/tests/test-phase-precondition.sh` on a clean main: **pass=75 fail=4**,
exit 1. The identical four failures appear when the suite is run from the
PHASE-GATE-IS-INVERTED-01 worktree, which is how the lane was cleared of causing them:

```
FAIL: G8:   spawn sentinel should exist (worker was spawned despite broken config)
FAIL: G11a: warn mode should spawn despite unexpected assert rc
FAIL: G11a: warn mode should journal unexpected_rc=127
FAIL: G11b: enforce mode should journal refused unexpected_rc=127
```

All four are the `unexpected_rc=127` family: the fixture assert exits 127 (command not found) and
the guard is expected to degrade — warn mode spawns anyway, enforce mode journals a refusal. The
observed journal line instead reads `project_root_guard status=foreign_env_overridden`, so the
fixture never reaches the rc-127 path at all: it is being stopped one step earlier by the project
root guard, because the suite runs the dispatcher against a temp repo while the ambient root is the
real checkout. Decide deliberately which is wrong — the fixture (it should pin both root vars) or
the guard (a temp-repo fixture is a legitimate foreign root) — and say which in report.md. Do NOT
edit the assertions to match current behaviour.
