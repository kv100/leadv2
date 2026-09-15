# MAIN-RED-SUITES-CENSUS-01 — census of the suites that gate lanes

Run by the lead directly, 2026-09-15, after the census lane `3631b93e` died on timeout with an
empty report.

## Why this population and not "all suites"
The first mission asked for *every* suite under `plugins/leadv2/scripts/tests/`. Counted after the
fact:

```
$ ls -1 plugins/leadv2/scripts/tests/test-*.sh plugins/leadv2/tests/test-*.sh | wc -l
593
```

593 suites at a 45s ceiling is up to 7.4 hours — no lane budget holds that, and no wording of the
mission fixes it. That is why the lane died, and the mission was wrong, not the worker.

The population that actually taxes the board is narrower: the set the gate selects, i.e. what
`run-core-offline.sh` runs. A suite red *outside* that set blocks no lane, so its redness has no
consumer. This census covers that set.

## Instrument
```
SUITE_TIMEOUT_S=120 timeout 1500 bash plugins/leadv2/scripts/tests/run-core-offline.sh
```
macOS (Darwin 25.6.0), repo `~/Projects/leadv2` on `main`, sharded by the runner itself.

## Result, with its boundary
```
[CORE-OFFLINE] suites passed=66 failed=27 missing=0 known_red_skipped=0
```

**93 suites selected, 93 ran, 27 red, 0 missing, 0 skipped**, at a 120s per-suite ceiling on macOS.
`missing=0` matters: the enumeration found every suite it names, so none of the 27 is an
`rc_127`-style absence masquerading as a failure.

Nothing here is a timeout: the whole run finished inside its 1500s outer bound.

## The 27, named
```
Codex quota guardrails (effort/circuit/hook)
T13 slice2 (arbiter bench-fallback + abandon dedup)
burn governor (BURN-GOVERNOR-01: 24h burn gate)
claim-evidence gate (CLAIM-EVIDENCE-GATE-01 preamble + round-1 lens)
core-offline cross-run exclusive lock (SUITE-SPEED-01)
deferred-GLM ladder (V3-GLM-LADDER-01)
dispatch arm vocabulary (kimi retirement)
dispatch refusal fallback chain
dod gate suite registration (both map forms + run-all selection)
idle-lead guard hook
journal honours the pinned root
landed-at-spawn (no terminal=landed at spawn; target repo keying)
lane placement pin (--resume-lane/--worktree)
lane trace instrument (Mission B: writer/concurrency/off-path/reader)
lane truth batch (log_path + quarantine convergence)
lane verdict three states (D2-UNBLIND-AND-THIRD-STATE-M0M1-01)
lane worktrees survive the sweepers (SWEEPER-LANE-SAFETY-01)
lane write-set admission block (LANE-WRITESET-REGISTRY-01)
parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)
per-turn injection dedup (HOOK-INJECT-DEDUP-01)
phase precondition guard matrix
product-close scopes a single-repo lane worktree
product-close waits for worker exit
report-only gate (REPORT-ONLY-GATE-01: report lane deliverable)
review round exhaustive/verify-only (REVIEW-ROUND1-EXHAUSTIVE-01)
shared-sink test guard (TESTS-POLLUTE-REAL-JOURNAL-01)
stop-gate autocommit on worker exit (V3-STOP-GATE-01)
```

## What this census does NOT establish
Cause class per suite. This run produced names and counts, not classifications — assigning
`never_reaches_subject` / `real_regression` / `environment_dependent` per suite requires reading
each failure, and the only prior attempt at that (`test-lane-writes-scoping.sh`, lane `6217107c`)
found the obvious hypothesis and then **falsified it**: an explicit fixture root changed nothing,
and the eight failures turned out to live in the dispatch and product-close paths, hidden behind
`/dev/null` redirection. Report: `docs/handoff/LANE-WRITES-SCOPING-SUITE-RED-ON-MAIN-01/report.md`.

Treat "27 red" as a measured population, not as 27 fixable bugs. Assume nothing about a cause you
have not read.

## Corroboration worth naming
Four of the 27 guard machinery that failed us in this very session, which is why the failures went
unnoticed — a suite nobody can read a verdict from stops reporting defects:

- `lane placement pin (--resume-lane/--worktree)` — a resume with an ABSOLUTE `@mission` path is
  refused as "absent from both lane worktree and main" while the file exists in the worktree, in
  the lane branch and on main. Cost ~30 minutes today. Row filed:
  `RESUME-LANE-REJECTS-AN-ABSOLUTE-MISSION-PATH-01`.
- `stop-gate autocommit on worker exit (V3-STOP-GATE-01)` — a resumed lane with no `--writes`
  journals `stop_gate_autocommit_skipped reason=empty_scope_writes_csv`, so the worker's changes
  can sit uncommitted and read as "no work".
- `dispatch refusal fallback chain` — the subject of row
  `DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01`, in flight.
- `report-only gate (REPORT-ONLY-GATE-01)` — the path a docs-only lane takes, which is how the
  first census lane was dispatched.

## Ranked fix plan
Cheapest-and-most-dangerous first. Each entry needs its cause READ before a lane is dispatched, and
each lane's `--writes` must name FILES — a directory in a write set prefix-matches everything
beneath it and serialises the whole board.

1. `lane placement pin (--resume-lane/--worktree)` — a defect with an independent live reproduction
   already in hand today. Start here: it is the only one of the 27 whose failure mode has been
   observed outside its own suite.
2. `stop-gate autocommit on worker exit` — same class, same session, silently loses work.
3. `product-close waits for worker exit` + `product-close scopes a single-repo lane worktree` —
   one owner, likely one cause.
4. Everything else: classify before touching. Several are plausibly `environment_dependent`
   (macOS), and the rows `TWELVE-LINUX-ONLY-SUITES-01` / `LAST-LINUX-RED-FAST-NAMES-01` already
   claim some of that ground — check them before opening anything new.
