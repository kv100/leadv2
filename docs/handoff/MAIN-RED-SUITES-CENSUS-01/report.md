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

The whole run finished inside its 1500s outer bound — but see the correction below before treating
all 27 as failures.

## Correction (same day, by the lead): the serial shard was measured at too low a ceiling
The 120s per-suite ceiling is below what at least one serial suite needs. `test-stop-gate.sh` was
re-run alone at a 600s budget and took **256 seconds** — so in the census run it was cut by the
ceiling, and its verdict there was a `timeout`, not a failure.

Re-run at a budget it fits in, it is **still rc=1**, on a named case:

```
test-stop-gate.sh rc=1 wall=256s
  - foreign-repo-journaled: post-fix did not pass (rc=1)
```

So for this one suite both things are true: it exceeded the ceiling AND it fails on merit.

### And then the caution was itself over-corrected — the original 27 holds
Every serial suite was re-run individually at a 900s budget. The verdicts reproduce the census
exactly: **2 green, 6 red**, the same split the sharded run reported.

```
test-codex-session-runner.sh    rc=0  wall=90s
test-lanes-snapshot.sh          rc=0  wall=69s
test-burn-governor.sh           rc=1  wall=149s
test-lane-truth-batch-01.sh     rc=1  wall=164s
test-no-work-terminal.sh        rc=1  wall=98s
test-report-only-gate.sh        rc=1  wall=116s
test-routing-enforcement-p1.sh  rc=1  wall=59s
test-stop-gate.sh               rc=1  wall=256s   (foreign-repo-journaled: post-fix did not pass)
```

Only two of the eight exceed the 120s ceiling (`stop-gate` 256s, `lane-truth-batch` 164s), and
neither changes verdict when given room. Five finish comfortably under the ceiling and were
honestly red in the census.

**The headline stands at 27 red of 93.** The ceiling risk was real, was measured, and did not move
the number. Recorded here because a caution that turns out to be unnecessary is still worth its
measurement — and because the next person reading "27" should know it survived a challenge rather
than never having been questioned.

Also noted: the suite names in `run-core-offline.sh` are descriptive labels, not filenames. The
label "product-close waits for worker exit" does not correspond to
`test-product-close-waits-for-worker-exit.sh` — that file does not exist. Map label → file through
the runner's own table before dispatching anything against a name from this report.

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

## Third correction (2026-09-16): two more of the 27 are green from main

Measured from `main` at `fa378236`, macOS Darwin 25.6.0, each suite run alone at a 600s ceiling:

```
test-dispatch-refusal-truth.sh      rc=0  wall=55s
test-writeset-admission-block.sh    rc=0  wall=17s
```

- `test-dispatch-refusal-truth.sh` is the suite behind the census label "dispatch refusal fallback
  chain". Its redness is **stale**: row `DISPATCH-REFUSALS-LIE-ABOUT-THEIR-CAUSE-01` was fixed and
  merged after this census was taken. The census was right when it ran and is wrong now.
- `test-writeset-admission-block.sh` is green **alone**. That is a weaker statement — it may be a
  fourth sharding-only red like the three named in the first correction. Not established either way;
  do not report it as fixed.

Running total of the 27 that are **not live defects in their own subject**: three sharding-only
(`test-core-offline-lock-01.sh`, `test-dod-gate-suite-registration.sh`,
`test-shared-sink-test-guard.sh`), one already-fixed (`test-dispatch-refusal-truth.sh`), one
superseded requirement encoded in a test (`test-burn-governor.sh`), and one unestablished
(`test-writeset-admission-block.sh`).

This does **not** mean "27 was wrong". The census measured what the gate does, and the gate really
did fail 27 suites that day. It means the number a lane must drive to zero is smaller than the
number of red lines, and the difference is made of stale reds, harness self-interference, and tests
that outlived their requirement. The closing number still comes from a re-measurement, never from
this arithmetic.

## A cluster the census could not see: the premise gate refuses the suites' own fixtures

Three measured suites fail for one shared reason that has nothing to do with their subject:

| Suite | Evidence |
|---|---|
| `test-landed-at-spawn.sh` | `premise_probe verdict=refused reason=backlog_row_not_found`, `dispatch exited 8 (expected 0)` — Face 3 of the Wave-0 diagnosis, which also verified the subject's target keying at `:481-495` is correct |
| `test-phase-precondition-bootstrap.sh` | every failure carries the same refusal at rc=8, across fresh Standard, after-remedies, false-claim and fresh Heavy cases |
| `test-glm-deferred-ladder.sh` | park rows and `codex_credits_empty` lines are all `<missing>` / `got 0`, because the dispatch that would write them was refused first |

`PREMISE-PROBE-BEFORE-A-LANE-IS-DISPATCHED-01` was added to stop a lane being spent on a dead
premise. It also refuses every test fixture that dispatches an ad-hoc mission, because a fixture has
no row in `docs/tasks.yaml`. The gate documents its own way out — `--no-probe-yet`, "the explicit,
audited escape hatch for an intentionally ad-hoc dispatch with no backlog row" — and the fixtures
were never taught to use it.

Cause class `never_reaches_subject` for all three. The fix is in the fixtures, and it should be **one
technique used three times**, not three inventions: Group A1 is establishing it for
`test-landed-at-spawn.sh`, and Group A2's mission requires reading what A1 landed before writing its
own.

Two suites from the original Group A list are therefore no longer A2's work, and two of A2's five
remaining suites collapse into this single cluster.
