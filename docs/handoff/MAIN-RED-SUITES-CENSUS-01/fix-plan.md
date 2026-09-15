# Plan: drive the gate-selected suite set from 66/93 to 93/93

Founder order 2026-09-15: fix all 93, start-and-close everything filed during the session, and fix
the plugin bugs seen along the way. This is the assembled plan; it is ordered so it can be stopped
after any wave without leaving a half-state.

## What "93/93" does and does not mean — read this first
The census ran **on macOS**. Three existing backlog rows describe the *opposite* population —
suites green on macOS and red on **Linux** (`TWELVE-LINUX-ONLY-SUITES-01`,
`LAST-LINUX-RED-FAST-NAMES-01`, `CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01`). They do not overlap with
the 27 below.

So: **93/93 green on macOS will not make CI green.** Two platforms, two populations, one number
each. Any claim that mixes them is the boundary error this census exists to prevent. Linux is a
separate order, not a free side effect of this one.

A suite whose failure is genuinely platform-bound counts as fixed when it **declares the
difference in the suite itself** — so the falsifiability check stops returning
`could_not_determine` — not when it is forced green.

## The 27, grouped by the file a fix would write
Grouping matters because `--writes` is prefix-matched: two lanes naming the same file serialise.
Each group below is ONE lane. Labels were mapped to filenames through the runner's own table — the
labels in `run-core-offline.sh` are descriptions, not filenames.

### Group A — `leadv2-dispatch-code.sh` (7 suites, one lane, the long pole)
```
test-claim-evidence-gate.sh        test-glm-deferred-ladder.sh
test-lane-placement-pin.sh         test-phase-precondition.sh
test-routing-enforcement-p1.sh     test-t13-slice2.sh
test-writeset-admission-block.sh
```
Also closes two rows filed this session, because they are defects in this same file:
- `RESUME-LANE-REJECTS-AN-ABSOLUTE-MISSION-PATH-01` — this *is* `test-lane-placement-pin`.
- `DISPATCH-REFUSAL-D2-STILL-MISMATCHES-INSIDE-A-FOREIGN-ROOT-01`.

### Group B — `leadv2-dispatch-product-close.sh` (3 suites, one lane)
```
test-lane-diff-single-repo.sh   test-report-only-gate.sh   test-stop-gate.sh
```
`test-stop-gate` fails on `foreign-repo-journaled`. Also the home of
`stop_gate_autocommit_skipped reason=empty_scope_writes_csv`, observed live twice today: a resumed
lane with no `--writes` leaves the worker's commits unmade, so real work reads as "no work".
Carries the filed row `PRODUCT-CLOSE-LANE-WRITES-ASSERTION-VERDICTS-01`.

### Group C — `leadv2-state-path.sh` (2 suites, one lane)
```
test-journal-honours-the-pinned-root.sh   test-landed-at-spawn.sh
```

**A, B and C share a theme**: root/path resolution — `foreign project root`, `pinned root`,
`/var` vs `/private/var`, `--resume-lane` joining an absolute path onto a worktree root. That is
four independent sightings today. **Before dispatching A, one diagnosis lane asks whether these
are one defect.** If they are, the fix is one change and the other lanes shrink to their tests. If
they are not, we have three named causes instead of a hunch. Either answer is worth the lane.

### Group D — 15 singletons, one file each, safe to run in parallel
```
test-codex-quota-guardrails.sh   → codex-task.sh
test-dod-gate-suite-registration → leadv2-dod-gate.sh
test-burn-governor.sh            → leadv2-fanout-lane-launcher.sh
test-dispatch-arm-vocabulary.sh  → leadv2-fanout.sh
test-shared-sink-test-guard.sh   → leadv2-freepool-gate.sh
test-parked-worker-resume.sh     → leadv2-helpers.sh
test-idle-lead-guard.sh          → leadv2-idle-lead-guard.sh
test-lane-verdict-three-states   → leadv2-lane-liveness.sh
test-review-round-exhaustive.sh  → leadv2-review-run.sh
test-no-work-terminal.sh         → leadv2-status-surface.sh
test-inject-dedup.sh             → leadv2-task-anchor.sh
test-lane-truth-batch-01.sh      → leadv2-test-target.sh
test-leadv2-trace.sh             → leadv2-trace.sh
test-worktree-lane-safety.sh     → leadv2-worktree-cleanup.sh
test-core-offline-lock-01.sh     → subject not resolved by grep; the lane names it first
```

## Plugin bugs seen during the session that are NOT in the 27
These were observed, not inferred. Each gets a row before it gets a lane.

1. ~~**A refused lane re-dispatches itself in a loop.**~~ **WITHDRAWN — misattributed, corrected
   2026-09-15 before any work was dispatched against it.** `e589f406` is not our lane. Its journal
   lives under `~/.claude/leadv2-state/getmany-followup-bot/`, and its write set is
   `src/booking/cancel-rebook-*.ts` — another session, another repo, retrying its own work against
   its own `blocked_by=89`. It also releases cleanly each time
   (`active_lane_released ... rows=1 removed=1`), so there is no leak. The lead's watcher globs
   `~/.claude/leadv2-state/*/tasks/`, which is why a peer's lane appeared in our event stream at
   all; the watcher is now scoped to `leadv2` and `persona-engine`. Recorded rather than deleted:
   the same glob will pull in a peer's events again for whoever reads this next.
2. **The review diff is scoped to the declared write set, so it manufactures false Highs.** Codex
   failed the quota lane with "the default refresher executable is missing" — the file was tracked
   in `HEAD` and in the index, but absent from the diff it was shown, because my `--writes` did not
   name it. The reviewer judged honestly what it was given. The diff should carry every file the
   lane actually committed.
3. **A lane's `--writes` cannot be widened after dispatch**, so a fix that turns out to need a new
   file either escapes the declared set or cannot be written. Related to 2, different mechanism.

## Order of work
- **Wave 0** — file the three rows above; dispatch the root/path diagnosis lane. Nothing else
  starts until that answer lands, because it decides whether A/B/C are one lane or three.
- **Wave 1** — A, B, C (or the single merged lane, if Wave 0 says so) + the first 5 of D. Cap 8.
- **Wave 2** — the remaining 10 of D.
- **Wave 3** — re-run the full census and publish the paired before/after with its boundary:
  suites selected, ran, red, ceiling, platform. **The number that closes this row is a
  re-measurement, not the sum of the lanes' claims.**

## Standing rules for every lane in this plan
- Never make a suite green by deleting an assertion, loosening a grep, or adding `|| true`. A
  suite that cannot be fixed honestly stays red and is named as still-red with its cause. That is
  a passing outcome.
- One negative control per independent check, RUN, with both outputs pasted. One mutation is not a
  control for N checks.
- Report the cause class per suite (`never_reaches_subject` / `real_regression` /
  `environment_dependent` / `rc_127` / `timeout`) before the fix appears in the diff.
- Every count carries its boundary: how many, of how many, at what ceiling, on which platform.
- `--writes` names FILES, never directories.

## Honest scale
27 suites, ~18 lanes, plus 3 new rows and a re-census. At today's observed rate — 30-60 minutes per
lane including review rounds, and several lanes needing a second round — this is many hours of
machine time, not a sprint to the end of this session. The waves are ordered so stopping after any
one of them leaves a coherent state and a true number.

---

# Wave 0 result, and what it changed (appended 2026-09-15, after the diagnosis landed)

## The diagnosis answered the blocking question: FOUR defects, not one
`docs/handoff/ROOT-PATH-RESOLUTION-ONE-DEFECT-OR-FOUR-01/report.md` (merged to main) returns
`VERDICT: N DEFECTS (n=4)` with a double-ended control: no single line or authority moves two faces,
and the lane falsified its own first proposal for Face 4 before replacing it.

| Face | Decision site | Mechanism | Owner |
|---|---|---|---|
| 1 | `leadv2-dispatch-code.sh:1303` (also 1313, 1321) | an absolute filesystem path is handed to `git ls-tree`, which needs a repo-relative tree path | Group A1 |
| 2 | `leadv2-journal.sh:48` (and :81-90) | inherited `CLAUDE_PROJECT_ROOT` outranks an explicit `LEADV2_PROJECT_ROOT` | Group C |
| 3 | `leadv2-dispatch-code.sh:9098`, no-row branch `:8410-8412` | the premise gate exits 8 before the ledger; target keying at `:481-495` is CORRECT | Group A1 |
| 4 | `leadv2-dispatch-product-close.sh:3756` | the normal path skips the foreign-repository pre-scan | Group B |

So **A, B and C stay three lanes.** The cheap outcome did not happen, and that is a result, not a
disappointment: we now have four named causes instead of one hunch.

## Re-measured from main by the lead, and it changed two of the lane's own caveats
The delivered probe was re-run from main at an 800s budget. All four faces reproduce:

```
FACE-1 RED rc=1 case=lane-placement-pin      [LANE-PLACEMENT-01] passed=18 failed=9
FACE-2 RED rc=1 case=journal-pinned-root     passed=3 failed=3
FACE-3 RED rc=1 case=landed-at-spawn         [LANDED-AT-SPAWN-01] passed=4 failed=8
FACE-4 RED rc=1 case=foreign-repo-journaled  12 passed(red->green), 1 failed
MACOS-VAR-PRIVATE CONTROL GREEN
  raw=/var/folders/gr/.../T//root-path-var-control.atp9dK
  physical=/private/var/folders/gr/.../T/root-path-var-control.atp9dK   same_directory=1
```

Two corrections to the lane's own report, in its favour:
- Face 1's baseline in the lane was `rc=124`, a **timeout**, and the lane honestly declined to use it
  as causal proof. From main it is a clean `rc=1`, 18 passed / 9 failed. The caveat is discharged.
- The lane's `/var` control could not obtain a `/var` spelling from its own `TMPDIR` and said so.
  From main it did: `raw=/var/...` vs `physical=/private/var/...`, `same_directory=1`. So the alias
  is **real on this host and still does not fire** at any of the four decision sites. That is now
  measured rather than assumed.

Face 3 remains `never_reaches_subject`: its fix is in the fixture, not the subject.

## The census's "27 red" needed correcting, twice more
1. **Three of the 27 are red only under the runner.** Measured alone at a 400s ceiling:
   `test-core-offline-lock-01.sh` 7s, `test-dod-gate-suite-registration.sh` 1s,
   `test-shared-sink-test-guard.sh` 2s — all rc=0, all far below the census's 120s ceiling, so time
   is not the explanation. For one of them the mechanism is now **named and controlled**:
   `run-core-offline.sh:179` re-execs as `env _LV2_CORE_OFFLINE_LOCK_HELD=1 …` and every suite body
   inherits the flag; the suite is rc=0 with a clean environment and rc=1 (pass=1 fail=2) with the
   flag set. It can never be green under the gate that selects it. Row
   `RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01`. The other two are still unexplained —
   green alone, green in parallel with each other twice, green under the lock flag, green under
   `LEADV2_TEST_CONTEXT=1` — and the lane must say so rather than fold them in.
2. **`test-burn-governor.sh` is not a bug at all.** All ten failures are one cause: the governor
   answers `reason=disabled`, because `leadv2-burn-governor.sh:112-118` records
   `BURN-GOVERNOR-OFF-BY-FOUNDER-ORDER-01` (2026-09-07) — the default was flipped 1→0 on the
   founder's explicit order after it killed `dispatch task=12f54b7c` (`burn24h=2579779075` over
   `hard=1300000000`). The suite encodes the superseded requirement, and the file's own line-17
   header still documents the old default. Fix the suite, guard the decision with a new case, never
   flip the default back.

## The label→subject mapping in the original plan was wrong in three places
The first pass mapped labels to subjects by grep. Running each suite and reading the failure moved
three of them:
- `test-landed-at-spawn.sh` — not `leadv2-state-path.sh`; it is Face 3, in `dispatch-code.sh`.
- `test-dispatch-arm-vocabulary.sh` — not `leadv2-fanout.sh`; case 10 proves both fanout call sites
  already forward `--task-class`, and case 9 fails because it never surfaces in the **dispatch**
  trace.
- `test-burn-governor.sh` — not `leadv2-fanout-lane-launcher.sh`; see above.

Group C therefore shrinks to **one** suite, and Group A grows. This is the second time in this plan
that a premise taken from a label did not survive contact with the mechanism.

## Coverage of the 27, as dispatched
**13 in flight**, across 8 lanes — codex-quota-guardrails · burn-governor · core-offline-lock ·
dod-gate-suite-registration · idle-lead-guard · journal-honours-the-pinned-root · landed-at-spawn ·
lane-placement-pin · leadv2-trace · worktree-lane-safety · parked-worker-resume ·
review-round-exhaustive · shared-sink-test-guard.

**7 waiting on Group A2** (they all write `leadv2-dispatch-code.sh`, which A1 holds): t13-slice2 ·
claim-evidence-gate · glm-deferred-ladder · dispatch-arm-vocabulary ·
dispatch-refusal-fallback-chain · writeset-admission-block · phase-precondition.

**4 waiting on Group B** (`leadv2-dispatch-product-close.sh`): lane-diff-single-repo ·
product-close-waits-for-worker-exit · report-only-gate · stop-gate.

**3 not yet assigned**, all root/path-shaped and needing their subject read first:
`test-lane-truth-batch-01.sh`; `test-lane-verdict-three-states.sh`, where every case returns
`unknown:contradictory_rows` and Test 9 reports `source=e0_contradiction_guard
reason=worktree_is_project_root`; `test-inject-dedup.sh`, whose hash-state file is not found under a
`/var/folders/...T//` path — note the doubled slash.

13 + 7 + 4 + 3 = 27.

## Plugin bugs found while running this plan
Beyond the two already listed above:

3. **`--no-probe-yet` means two different things.** The flag exists on `task-add.sh` and on
   `leadv2-dispatch-code.sh` with different semantics, and a row created by the first is refused by
   the second: the dispatch gate honours its own flag only when NO row was found (`:8366-8373`),
   while a row that exists without a probe takes the `no_premise_probe` branch at `:8438`, whose
   remedy text lists three fixes and not the identically-named flag. Cost one dispatch cycle.
   Row `NO-PROBE-YET-MEANS-TWO-DIFFERENT-THINGS-01`.
4. **The report-only gate refuses a file that IS in the declared write set.** Lane `71f133b2` — the
   diagnosis lane itself — declared two files in `--writes`, committed exactly those two, and was
   refused `unscoped_lane_work` with `declared=<the lane-deliverable path>`. The gate validates
   against `--lane-deliverable`, not against `--writes`, so a report lane cannot ship the instrument
   its own mission demands. A completed 2767-second lane was discarded for a gate error, and the
   lead verified and merged it by hand. Row
   `REPORT-ONLY-GATE-REFUSES-A-FILE-THAT-IS-IN-THE-DECLARED-WRITE-SET-01`. It is the live subject of
   census-red suite `test-report-only-gate.sh`, so it and Group B should be settled together.
5. **The runner leaks its lock flag into the suites it runs** — see the census correction above.

## Revised order
- **Wave 1 (running)**: A1 · C · five Group-D lanes · the runner lock-leak lane. Cap 8.
- **Wave 2**: A2 (after A1 releases `dispatch-code.sh`) · B (which also carries plugin bug 4) ·
  the three unassigned suites once their subjects are read.
- **Wave 3**: unchanged — re-run the census and publish the paired before/after with its boundary.
  Ledger row `SD-REDSUITES-RECENSUS-CLOSES-THE-ROW-01` holds the GO-condition and the rollback.
