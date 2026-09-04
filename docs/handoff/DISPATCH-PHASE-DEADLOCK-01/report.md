# DISPATCH-PHASE-DEADLOCK-01 — round 2 report

Lane: PHASE-BOOTSTRAP-PROVE-05 (worktree pin; lane root DISPATCH-PHASE-DEADLOCK-01 content
brought here). Commits: `fe17d83` (round-1 salvage `32571fb` cherry-picked onto current main,
clean), `2a293d8` (round-2 fix), plus this report.

## 1. The founder's "green on broken" measurement does not reproduce from the salvaged bytes

From `32571fb` exactly as salvaged, reverting both production files to main makes the suite
**RED** — measured before any round-2 edit, in this worktree:

```
$ git checkout main -- plugins/leadv2/scripts/leadv2-phase-record.sh \
                       plugins/leadv2/scripts/leadv2-dispatch-code.sh
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
  FAIL: bootstrap lane should be admitted (rc=3, out=missing=classify,plan,gate1)
  FAIL: bootstrap admission should journal phase_precondition_bootstrap
  FAIL: plan recorded from a brief should carry proof: attested (…proof: unverified)
  FAIL: brief-satisfied plan should drop out of missing=, only gate1 left
  FAIL: assert after running the printed remedies should admit (rc=3, …)
  FAIL: gate1 recorded via --reason should carry proof: attested (file: )
[PHASE-PRECONDITION-BOOTSTRAP] pass=9 fail=6
RC=1
```

9 pass / 6 fail / rc=1 — the suite as salvaged already discriminates fixed from broken. The
DISPATCH-PHASE-DEADLOCK-01 worktree's committed bytes are identical to `32571fb` (verified by
diff). Most likely the measurement ran against the lane's pre-salvage staged state or an earlier
iteration of the test file; it cannot be reproduced from the salvage commit itself. Said plainly:
round 1's suite was NOT lying green on main — but it was also not sufficient, see §2.

## 2. What round 1 actually got wrong (found by running, not reading)

The real deadlock survived round 1 on the **real dispatch path**. `leadv2-dispatch-code.sh`
records `classify` at `:6622` **before** calling `_phase_precondition_guard` at `:6632`, so by
the time `cmd_assert` ran, every brand-new lane already had exactly one record and the
zero-record bootstrap probe could never fire. Measured on main:

```
FAIL: sonnet argv=<no argv captured> dispatch_out=[leadv2-dispatch-code] ERROR:
dispatch refused: missing mandatory phases: diverge,plan,gate1
```

(`test-effort-routing.sh`, red on main — the fixture dispatches through the REAL dispatcher into
a fresh git repo, records classify, then gets refused by the guard.)

Round 2 fix (`2a293d8`):
- `leadv2-phase-record.sh`: new `is-bootstrap <sig8>` subcommand (exit 0 iff phases.d absent or
  empty) and `assert --at-bootstrap` — caller-attested bootstrap, honoured for `--pre-build`
  scope only.
- `leadv2-dispatch-code.sh`: `cmd_resolve` probes `is-bootstrap` **before** the classify write;
  `cmd_advance_arm` does the same (it records no classify). The guard forwards the answer to
  assert. A lane with pre-existing history is probed non-bootstrap and enforced exactly as
  before; full-scope asserts ignore the flag entirely (unit test 7b).

## 3. The round-2 bar, with runs

Revert both production files to main ⇒ RED:

```
$ git checkout main -- <leadv2-phase-record.sh> <leadv2-dispatch-code.sh>
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
[PHASE-PRECONDITION-BOOTSTRAP] pass=10 fail=11
RED-RC=1
```

Restore ⇒ GREEN (now 21 assertions; 6 added for the round-2 seam):

```
$ git checkout HEAD -- <both files>
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-phase-precondition-bootstrap.sh
[PHASE-PRECONDITION-BOOTSTRAP] pass=21 fail=0
GREEN-RC=0
$ git status --short | grep -v '^??' | wc -l
0
```

The live consequence — `test-effort-routing.sh` is green again (was red on main, §2):

```
SUMMARY: pass=9 fail=0
RC=0
```

## 4. Autopsy of the round-1 assertions (bar item 4)

All 15 round-1 assertions drive the real `leadv2-phase-record.sh` binary against a throwaway
state root — none reimplements the logic locally and no fixture pre-creates the artifacts the
gate checks. The honest classification, against main's code:

- **6 of 15 pin the fix** (they FAIL on main): T1a bootstrap admission rc, T1c bootstrap journal
  event, T3a plan `proof: attested`, T3b brief satisfied drops out of missing=, T4 remedy clears
  the refusal, T4 gate1 `proof: attested`.
- **8 of 15 are enforcement regression guards** (pass on both — they assert refusal behaviour
  main gets right): T2 same-lane-later refuse rc=3 + missing list, T3b negative control
  (non-brief name → unverified), T4a pre-remedy refuse, T4b gate1 without artifact/reason exits
  4, T5 genuinely-skipped lane refused rc=3 + missing list.
- **1 of 15 was vacuous**: T1b ("bootstrap check must run BEFORE any phase file is written") —
  it passed on main only because main's assert writes nothing at all; it can never catch a fix
  that side-effects, only reward one that doesn't.

So: not "most of them vacuous" — but the suite's discrimination came entirely from those 6, and
none of the 15 could see the dispatcher-path deadlock in §2, because they never drive
`leadv2-dispatch-code.sh`. Round 2's added assertions (is-bootstrap probe flip, `--at-bootstrap`
admission, full-scope non-leak, no-flag refusal) close that gap at the unit level, and
`test-effort-routing.sh` proves it through the real dispatcher.

## 5. test-phase-precondition.sh — pre-existing reds shared with main; G2 fixed here

Ran the suite on my branch and on main (revert, run, restore). On main: **pass=71 fail=8**
(G2 ×3, G3, G8, G11a ×2, G11b). On my branch, same 8 before the G2 fix — zero regressions
from this lane. After the G2 fix, my branch:

```
[PHASE-PRECONDITION] pass=75 fail=4   RC=1
  FAIL G8, FAIL G11a (×2), FAIL G11b
```

- **G2 codified the deadlock itself**: it expected a brand-new lane (zero phase records) to be
  refused. Fixed in this round: the fixture now seeds `classify` (same sig pipeline as G1,
  verified `7c9da953` matches dispatch's own sig8) so G2 asserts what it always meant — a
  STARTED lane missing plan/gate1 is still refused. All 3 G2 assertions now pass.
- **G3 flipped green between runs without any code change** — it is flaky via the same leaked
  state as G8 (below), not a code difference.
- **G8/G11a/G11b are pre-existing on main and out of this lane's writeset.** Root cause
  (partial, from failure evidence): the e2e cases are not hermetic — `project_root_guard …
  status=foreign_env_overridden env_root=/private/tmp/... cwd_root=.../PHASE-BOOTSTRAP-PROVE-05`
  shows the fixture's `LEADV2_PROJECT_ROOT` is overridden by the cwd root for parts of the
  dispatch, so admission receipts (`docs/handoff/dispatch-*/admission-receipt.yaml` found in the
  real tree for fixture sigs) and lane state leak across runs. G11a/G11b match the documented
  baseline red (foreign-failure fixture, see memory: run-all changed pre-existing reds).

## 6. Falsification set (raw)

- `bash -n`: leadv2-phase-record.sh OK · leadv2-dispatch-code.sh OK ·
  test-phase-precondition-bootstrap.sh OK · test-effort-routing.sh OK ·
  test-phase-precondition.sh OK.
- `python3 -m py_compile`: n/a — no Python files changed.
- Changed-scope runner: this lane IS the phase-guard change; the changed-scope equivalents were
  run directly above (bootstrap suite, effort-routing, phase-precondition) — all three suites
  whose stems match changed files.
- Red/green proof: §3 (bootstrap suite) and §2/§3 (effort-routing red on main → green here).

## 7. Notes and deviations

- Writeset deviations, both test files, both forced by the founder's green bar:
  `test-effort-routing.sh` (one-line cleanup-trap defusal: the async `leadv2-lane-pulse-watch.sh`
  armed at `:5243` can still be writing pulse/inbox artifacts under TMP when the suite exits;
  under `set -e` a racing `rm` turned a 9/9-green run into rc=1 — measured) and
  `test-phase-precondition.sh` (G2 seed, §5).
- Lane litter: running the dispatcher in repros left fixture lane worktrees under
  `.claude/worktrees/<sig8>` (e.g. `7c9da953`) — that is dispatch's own "lane_worktree_left"
  behaviour, not state-root writes.
- `is-bootstrap` failure semantics: any error (rc ≥ 2, e.g. unknown command on an old binary)
  reads as NOT-bootstrap → full enforcement — fail-closed.
