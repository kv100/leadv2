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

1. **A refused lane re-dispatches itself in a loop.** `e589f406` emitted
   `terminal=refused cause=writeset_overlap` at 14:15, 14:20 and 14:21 — three identical refusals
   for work that had already landed under `ce3da635`. Nothing reaps the retry.
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
