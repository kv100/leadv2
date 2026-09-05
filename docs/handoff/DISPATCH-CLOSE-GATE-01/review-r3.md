# DISPATCH-CLOSE-GATE-01 — adversarial review, round 3

**VERDICT: fail**

Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/DISPATCH-CLOSE-GATE-01` @ `70b7749`
Reviewed: `git diff origin/main...HEAD -- plugins/ tests/ .gitignore` (8 files, +1054/-9)

Every mutation below was applied INSIDE the function body of the **production** file, in a byte
copy of the lane at `…/scratchpad/lane3` that reproduces the lane baseline exactly
(`test-mission-writeset.sh` 18/0, `test-red-proof-gate.sh` 19/0 under `/bin/bash` 3.2.57). Every
mutation asserts its anchor count and hard-exits on a zero match. No source in the lane was
modified; `git status --porcelain plugins/ tests/ .gitignore` is empty before and after.

| Item asked | Verdict |
|---|---|
| 1 — red-proof dir resolution + FP count over the real dirs | **BROKEN** (0 false positives, but 0 true positives — the gate is inert) |
| 2 — extractor precision on the mission sweep, bar 6/6 | **BROKEN** — 3/5, and the review's own named FP is unfixed |
| 3 — the downgrade has a control | **BROKEN** — the exact mutation still leaves 19/0 and 18/0 |
| 4 — specimens tracked in git | **WORKS** |
| 5 — guarded `source` for the three consumer repos | **BROKEN** — fixed in product-close, *reintroduced fatally* in the dispatcher |
| 6 — `--scope changed` from the real dirty lane | **WORKS** |
| 7 — no test writing into the production scripts dir | **WORKS** |
| (regression watch) round-2 win: 3 call sites deleted → 16/2 | **WORKS** |
| (regression watch) the two real specimens | **WORKS** |
| (new) red-proof artifacts for round 3 | **BROKEN** — `round3-red/` does not exist; `round2-red/` holds only GREEN runs |

---

## Item 1 — red-proof directory resolution: BROKEN (inert, not false-positive)

The direction of the fix is right: `leadv2-dispatch-product-close.sh:3257-3262` now keys on
`FOUNDER_TASK_ID` → `${ROOT}/docs/handoff/<TASK-ID>`, and `lib/leadv2-red-proof.sh:71` scans both
`red/` and `round*-red/`. False positives are gone. So are true positives.

Sweep of the production function over **every** handoff dir in the main checkout:

```
### dirs scanned=758 fired=1
FIRED docs/handoff/dispatch-8c4b0f7c/
    unproven: N4-1 — reserve arithmetic now yields when both sides fit
    unproven: N4-2 — own=1..3 × foreign=1..5 matrix
    unproven: MU3 / MU6 — mutation controls for two round-4 fixes that shipped without one
```

The single dir that fires is a `dispatch-<sig8>` dir — **the dir the round-3 fix stopped looking
at.** The claim file is `dispatch-8c4b0f7c/developer.full.md`. Census of where worker claims and
RED proofs actually live:

```
non-dispatch (founder task-id) dirs=107   claimfiles=0
dispatch-<sig8> dirs=651                  claimfiles=1
dirs with a red/ or round*-red/ child     = 1 of 758   (docs/handoff/BROAD-STATUS-ROWS-02/round3-red)
git ls-files 'docs/handoff/*/red/*' 'docs/handoff/*/round*-red/*'  ->  (empty)
```

Round 2 found the artifacts under the task id and the claims under the dispatch sig. Round 3 moved
**both** lookups to the task id, so the gate now reads claims from a directory where a worker
deliverable has never once been written (0 of 107). Live probe on the richest real lane in the repo
— five fix rounds, five review rounds, a real `round3-red/`:

```
$ leadv2_red_proof_unproven docs/handoff/BROAD-STATUS-ROWS-02
UNPROVEN_OUT=[]
```

Nothing. And even if a claim were found, `has_red` cannot succeed on the live path: RED logs are
written into the lane **worktree**, are matched by `.gitignore:40` (`docs/handoff/*/*`), are never
committed (`git ls-files` above is empty), and product-close runs with `ROOT` = the main checkout
(`leadv2-dispatch-code.sh:4553` passes `PROJECT_ROOT`). Both halves of the cross-check point at
directories that are empty in production.

Separately, the "is this a worker claim" filter is one heading style away from reproducing round 2's
semantic inversion. `lib/leadv2-red-proof.sh:43` rejects filenames containing "mission"; `:45`
requires `DELIVERABLE_COMPLETE`. A **reviewer's** report carries that marker by protocol:

```
$ cat scratch/fp/review-r3.md
## [Critical] the extractor still refuses this lane's own mission
…
DELIVERABLE_COMPLETE
$ leadv2_red_proof_unproven scratch/fp
unproven: the extractor still refuses this lane's own mission
```

33 `review-*.md` files in `docs/handoff/` already carry `DELIVERABLE_COMPLETE`. Today none of them
uses `## [Critical]` headings, which is the only reason the sweep is clean — a review *finding* is
being read as a worker's *claimed fix*, which is exactly the inversion that produced 4/4 false
positives in round 2. The filter is luck, not semantics.

## Item 2 — extractor precision: BROKEN (3/5, bar was 6/6)

Sweep of every mission-shaped doc in `docs/handoff/*/` carrying a `LANE_WRITES:` line, each checked
against its own declared write set, using the production `leadv2_writeset_missing`:

```
### mission-shaped corpus: 287 files ; distinct refusals: 5
REFUSED docs/handoff/dispatch-237f8026/lane-mission.md
    docs/handoff/one-review-path-2026-08-06/codex-capability.md          <- TRUE  ("Write the answers … to `…`")
REFUSED docs/handoff/dispatch-604ed16d/lane-mission.md
    docs/handoff/DISPATCH-KIMI-ARM-MISMATCH-01/deliverable.md            <- TRUE  ("Deliverable at `…`")
REFUSED docs/handoff/ANTI-SILENCE-STATUSLINE-01/fix-round-3.md
    docs/handoff/ANTI-SILENCE-STATUSLINE-01/round3-red/                  <- TRUE  (LANE_WRITES has no docs/ entry)
REFUSED docs/handoff/DISPATCH-CLOSE-GATE-01/fix-round-2.md
    lib/leadv2-lane-guard.sh                                             <- FALSE (the review's own named FP)
REFUSED docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-4.md
    plugins/leadv2/scripts/docs/
    plugins/leadv2/scripts/.claude/                                      <- FALSE
### precision = 3/5
```

Widening the corpus to all 632 files with a `LANE_WRITES:` line adds a sixth refusal
(`DISPATCH-CLOSE-GATE-01/review-r2.md` → `docs/handoff/DISPATCH-CLOSE-GATE-01/round3-red/`), i.e.
3/6 — the same number round 2 reported.

The FP round 2 named by name is **unfixed**. `fix-round-2.md:99` reads:

> the pre-correction form of `fix-round-5.md` refused with `lib/leadv2-lane-guard.sh` named

The round-3 widening at `lib/leadv2-mission-writeset.sh:39-48` only inspects the text *before* the
backtick (`add_path`, `:62-64`); here the disambiguating word ("named") comes *after* it, so
`citation_re` never sees it. Dispatching round 4 of this very lane from its own brief would still be
refused.

The second FP is new in kind: `DISPATCH-PIN-CLUSTER-01/fix-round-4.md:81` says
"**… `plugins/leadv2/scripts/docs/` or `plugins/leadv2/scripts/.claude/` is tracked**" — a
*forbidden* condition inside Done-means, extracted as a *required write*.

`leadv2-dispatch-code.sh:649` ships `REQUIRE_MISSION_WRITESET="${LEADV2_REQUIRE_MISSION_WRITESET:-1}"`
— **on by default** at 3/5 precision, against the review's explicit "6/6 or it stays off".

## Item 3 — the downgrade control: BROKEN

The review named the mutation: remove the five `${_pc_unproven_suffix}` interpolations from the
`_dl_note` calls, i.e. the entire user-visible effect of Mechanism 2. Round 3 hoisted the
interpolation into `_pc_evidence_with_unproven` (`:3275`) and asserted *that helper*. The five call
sites (`:3299, :3317, :3321, :3333, :3359`) are still untested. Unwrapping all five — the same
end state the review asked about, with the helper left intact but with zero callers:

```
unwrapped call sites: 5
=== MUT-A redproof ===
PASS: C5 wiring: rendered close note (via _pc_evidence_with_unproven) carries the unproven suffix
PASS: control C5-note: suffix append removed from the render helper -> note loses it (caught, would be red)
SUMMARY: pass=19 fail=0
=== MUT-A writeset ===
SUMMARY: pass=18 fail=0
```

Both suites stay fully green while no close note in production can ever carry an `unproven=` suffix
again. The commit message of `70b7749` states "Centralized the unproven-suffix rendering into one
function (`_pc_evidence_with_unproven`) so all five close-note call sites are proven by one
behavioural control" — that sentence is false, and the run above is the counter-example.

The helper itself *is* covered (this mutation, applied to the production file, goes red — so the
in-suite control is real, not theatre):

```
=== MUT-B: strip the suffix append inside _pc_evidence_with_unproven ===
NOTE:diff=abc123
FAIL: control C5-note: mutation source pattern not found (helper drifted, update mutation)
SUMMARY: pass=17 fail=2
=== restored === SUMMARY: pass=19 fail=0
```

Second gap in the same test: `test-red-proof-gate.sh:206-207` and `:248-249` `eval` the C5 block with
`FOUNDER_TASK_ID=""` and `LANE_NAME=""`, so `_pc_redproof_dir` falls through to `${HANDOFF}` — the
**only** branch production never takes. The one live path (`:3259`,
`${ROOT}/docs/handoff/${FOUNDER_TASK_ID}`) has no coverage at all, which is why Item 1's inertness
survived a green suite.

## Item 4 — specimens tracked: WORKS

```
$ git ls-files docs/handoff/DISPATCH-CLOSE-GATE-01/
docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-4.md
docs/handoff/DISPATCH-CLOSE-GATE-01/specimens/fix-round-5.md
$ git check-ignore -v …/specimens/fix-round-4.md …/specimens/fix-round-5.md ; echo rc=$?
rc=1
```

Both tracked, neither ignored, and both still byte-identical to their originals (`diff -q` →
`R4 IDENTICAL`, `R5 IDENTICAL`) — not fitted to the code. The suite reads the tracked copies
(`test-mission-writeset.sh:246-248`), so the two assertions survive a fresh checkout.

## Item 5 — guarded `source`: BROKEN (fixed in one file, made fatal in the other)

`leadv2-dispatch-product-close.sh:43-48` is now guarded with the repo's canonical-root fallback —
correct, and matching `_PARKED_DETECT_SH` at `:49-53`.

But the same commit added **two unguarded** sources to the dispatcher:

```
leadv2-dispatch-code.sh:459   source "${SCRIPT_DIR}/lib/leadv2-mission-writeset.sh"
leadv2-dispatch-code.sh:461   source "${SCRIPT_DIR}/lib/leadv2-red-proof.sh"
```

`SCRIPT_DIR` (`:432`) is `dirname "${BASH_SOURCE[0]}"`, which for a per-file symlink is the
*consumer's* dir. All three consumer repos symlink per file and carry only one lib:

```
persona-engine/.claude/scripts/leadv2-dispatch-code.sh -> …/Projects/leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh
persona-engine/.claude/scripts/lib/  ->  leadv2-parked-detect.sh        (that is the whole listing)
respiro-ios/.claude/scripts/lib/     ->  leadv2-parked-detect.sh
m3-market/.claude/scripts/           ->  no lib/ at all
```

Reproduced on a faithful consumer layout (per-file symlinks of every sibling + `lib/` containing only
`leadv2-parked-detect.sh`), `bash -x`, last four trace lines:

```
+ source …/fakerepo2/.claude/scripts/leadv2-portable-lock.sh
++ LV2_LOCK_STALE_S=120
+ source …/fakerepo2/.claude/scripts/lib/leadv2-mission-writeset.sh
.claude/scripts/leadv2-dispatch-code.sh: line 459: …/lib/leadv2-mission-writeset.sh: No such file or directory
$ echo rc=$?   ->   rc=1
```

The dispatcher **dies at line 459** and never reaches line 461, because
`leadv2-helpers.sh:10` (`set -euo pipefail`, sourced at `leadv2-dispatch-code.sh:442`) turns `-e` on
despite the `# NO -e` comment at `:277`. This is not a degraded gate — it is the dispatcher failing
to start in `persona-engine`, `m3-market` and `respiro-ios`. The repo's own convention is ninety
lines below at `:553` (`_REPORT_DELIVERABLE_SH` with the `LEADV2_CANONICAL_ROOT` fallback); the new
lines ignore it.

On a layout without helpers present the failure mode is worse than fatal — it is a lying green:

```
.claude/scripts/leadv2-dispatch-code.sh: line 5930: leadv2_red_proof_unproven: command not found
red_proof_ok task=T1
rc=0
```

`cmd_close_gate` (`:5915-5934`) reports `red_proof_ok` for a handoff dir holding an unbacked
`## [Critical]` claim, purely because the library never loaded.

## Item 6 — `--scope changed` from the real dirty lane: WORKS

The lane's working tree is docs-only dirty (18 files, all `docs/`). Running the production selection
block verbatim (`tests/run-all.sh:141-181`, extracted by line range and `source`d with the real
`EXTRA_SUITE_MAP` from `:105-125` and `ROOT` = the lane):

```
union changed set includes:
  plugins/leadv2/scripts/leadv2-dispatch-code.sh
  plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
  plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh
  plugins/leadv2/scripts/lib/leadv2-red-proof.sh
  plugins/leadv2/scripts/tests/test-mission-writeset.sh
  plugins/leadv2/scripts/tests/test-red-proof-gate.sh
SELECTED (7):
  …/tests/test-lane-pulse-watch.sh
  …/tests/test-single-lead-beat-loop.sh
  …/tests/test-phase-precondition.sh
  …/tests/test-freepool-capability-floor.sh
  …/tests/test-model-select-telemetry.sh
  …/tests/test-mission-writeset.sh          <-- new
  …/tests/test-red-proof-gate.sh            <-- new
```

Both new suites are selected from the actual dirty lane. Carried C4 is genuinely closed. (A full
`tests/run-all.sh --scope changed` was also started and hit the 540 s cap inside
`run-core-offline.sh`; the selection above is the real block, run against the real git state.)

## Item 7 — no test writing into the production scripts dir: WORKS

`test-mission-writeset.sh:200-208` now builds `MUT_DIR="$(mktemp -d …)"`, symlinks every sibling
entry, and writes only the mutated dispatcher into `TMPDIR`. `git status --porcelain plugins/` is
empty and no stray copy exists in `plugins/leadv2/scripts/`. Same discipline in
`test-red-proof-gate.sh:149` and `:227/:263`.

## Regression watch — the round-2 win: WORKS

```
M1 applied: 3 call sites deleted (2 identical + 1 compound, anchors asserted)
FAIL: wiring: architect_prepass rc=0 out=… status=disabled reason=kill_switch
FAIL: control C1-wiring: mutation source pattern not found (dispatcher drifted, update mutation, rc=2)
SUMMARY: pass=16 fail=2
=== RESTORED === SUMMARY: pass=18 fail=0
```

Specimens run against the **real on-disk originals**, not the tracked copies:

```
$ … mission-writeset-check docs/handoff/ANTI-SILENCE-STATUSLINE-01/fix-round-4.md
mission_writeset_ok                                          (rc=0)
$ … mission-writeset-check docs/handoff/DISPATCH-PIN-CLUSTER-01/fix-round-5.md "<pre-correction csv>"
mission_writeset_refused missing=lib/leadv2-lane-guard.sh    (rc=1)
```

## Artifact-honesty check: BROKEN

`fix-round-3.md` Rules: "Every fix keeps a control you RUN … Logs in `round3-red/`."

```
$ ls docs/handoff/DISPATCH-CLOSE-GATE-01/
red  round2-red  specimens
$ ls round3-red
ls: round3-red: No such file or directory
$ ls round2-red
mission-writeset-green.log   red-proof-green.log
$ tail -1 round2-red/*.log
SUMMARY: pass=18 fail=0
SUMMARY: pass=14 fail=0
```

Round 3 shipped **zero** RED artifacts. `round2-red/` — a directory whose name asserts a RED run —
contains only two passing runs. That is precisely the shape the brief listed as a fake control ("a
`roundN-red/` artifact that records a *passing* run under a RED header"). None of these logs is
tracked in git either, so the mechanism they are supposed to feed can never read them.

---

# Findings

## Critical

**C1 — `plugins/leadv2/scripts/leadv2-dispatch-code.sh:459,461` — unguarded `source` kills the
dispatcher in all three consumer repos.**
`SCRIPT_DIR` resolves to the consumer's `.claude/scripts` for a per-file symlink; neither
`lib/leadv2-mission-writeset.sh` nor `lib/leadv2-red-proof.sh` exists there (verified in all three
repos), and `leadv2-helpers.sh:10`'s `set -e` makes the failing source fatal — traced run above,
`rc=1` at line 459. This is the review's item 5 defect, fixed in product-close and reintroduced,
worse, in the dispatcher.
*Fix:* use the file's own established idiom (`:553`) for both lines —
`_X="${SCRIPT_DIR}/lib/…"; [[ -f "${_X}" ]] || _X="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/…"; [[ -f "${_X}" ]] && source "${_X}"`
— and add a suite assertion that runs the dispatcher from a symlink-only layout.

**C2 — `leadv2-dispatch-product-close.sh:3257-3262` + `lib/leadv2-red-proof.sh:40-56` — Mechanism 2
is inert on the live path.**
Claims are read from `docs/handoff/<TASK-ID>/`, where 0 of 107 real task dirs hold a worker
deliverable; proofs are read from `<TASK-ID>/{red,round*-red}/`, present in 1 of 758 dirs and tracked
in 0. Live probe on `BROAD-STATUS-ROWS-02` returns empty. The gate cannot fire in production.
*Fix:* read claims from the dispatch dir the worker actually writes (`${HANDOFF}`, which already
holds `developer.full.md`) and proofs from the task-id dir **and** the lane worktree; assert it
against `dispatch-8c4b0f7c` + `BROAD-STATUS-ROWS-02` as an on-disk specimen pair, the way Mechanism 1
uses its specimens.

**C3 — `leadv2-dispatch-product-close.sh:3299,3317,3321,3333,3359` — the five call sites that produce
the founder-visible effect have no coverage.**
Unwrapping all five leaves `test-red-proof-gate.sh` at 19/0 and `test-mission-writeset.sh` at 18/0
(MUT-A above). The commit message claims the opposite.
*Fix:* assert the five call sites themselves — e.g. extract each `_dl_note` line and check it routes
through `_pc_evidence_with_unproven`, driven from the same `eval`'d block with a stubbed `_dl_note`
that records its evidence argument — and prove it by unwrapping them, not by editing the helper.

**C4 — `lib/leadv2-mission-writeset.sh:39-48,62-64` — extractor precision 3/5 with
`REQUIRE_MISSION_WRITESET` defaulting to 1 (`leadv2-dispatch-code.sh:649`).**
The review's own named false positive (`fix-round-2.md:99`) is unrefuted, and a second FP class
(a forbidden path stated inside Done-means) appeared. A refused good dispatch is how this mechanism
gets switched off permanently.
*Fix:* either reach 6/6 — scan the whole line, not just the prefix, for the disambiguators, and skip
Done-means clauses whose verb is negative ("is tracked", "must not", "no … exists") — or set the
default to `0` in the same commit and say so.

**C5 — `docs/handoff/DISPATCH-CLOSE-GATE-01/` — no `round3-red/`; `round2-red/` records only passing
runs.**
A required round-3 deliverable is absent, and the one directory named for RED evidence contains two
`SUMMARY: fail=0` logs. Nothing in this round is backed by an artifact the author produced.
*Fix:* produce `round3-red/` with the mutation applied inside the production function body, the RED
output, the revert, and the GREEN output, one file per fix, and `git add` them individually.

## High

**H1 — `leadv2-dispatch-code.sh:5915-5934` (`cmd_close_gate`) — prints `red_proof_ok` when the library
never loaded.** Observed: `line 5930: leadv2_red_proof_unproven: command not found` followed by
`red_proof_ok task=T1`, rc=0, on a dir holding an unbacked `## [Critical]` claim.
*Fix:* `declare -F leadv2_red_proof_unproven >/dev/null || { log_err "close-gate: red-proof lib unavailable"; exit 2; }` before the call. The same guard is needed at
`leadv2-dispatch-product-close.sh:3263`, where the missing function currently degrades silently to
"nothing unproven".

**H2 — `lib/leadv2-red-proof.sh:43-45` — the claim/brief filter is heading-style luck, not semantics.**
A reviewer's `review-rN.md` carries `DELIVERABLE_COMPLETE` by protocol (33 such files today) and
would have its findings reported as the worker's *claimed fixes* — demonstrated above. Only the
current absence of `## [Critical]` headings in review reports keeps the sweep clean.
*Fix:* key on the author role, not the filename+marker — restrict to the dispatch dir's
`<role>.full.md` / `<role>.summary.md` produced by the worker arm, or require an explicit
`## [Fixed]`-style marker the worker emits deliberately.

**H3 — `test-red-proof-gate.sh:206-207,248-249` — the C5 block is only ever evaluated with
`FOUNDER_TASK_ID=""`.** The fallback branch (`_pc_redproof_dir="${HANDOFF}"`) is tested; the branch
production always takes (`${ROOT}/docs/handoff/${FOUNDER_TASK_ID}`) is not. That is why C2 shipped
under a green suite.
*Fix:* add a case with `FOUNDER_TASK_ID` set and `ROOT` pointing at a fixture tree, asserting the
resolved dir.

## Medium

**M1 — `lib/leadv2-mission-writeset.sh:203-211` — the suggested corrected `LANE_WRITES:` line pastes a
path that does not exist.** For the round-5 specimen it emits `…,lib/leadv2-lane-guard.sh`, the short
form scraped from prose, not `plugins/leadv2/scripts/lib/leadv2-lane-guard.sh`. A lead pasting it
declares a non-existent path into a value that also drives worktree and diff scoping.
*Fix:* resolve each missing path against the repo (`git ls-files`) before emitting it, and drop or
mark any that does not resolve.

**M2 — `tests/run-all.sh:184` — `for suite in "${SUITES[@]}"` is an unbound-variable abort under bash
3.2 + `set -u` when zero suites are selected.** Confirmed: `/bin/bash -c 'set -u; declare -a A=(); for x in "${A[@]}"; do :; done'` → `A[@]: unbound variable`. Pre-existing, but this diff rewrites the
block that decides whether `SUITES` can be empty, so it belongs to this change.
*Fix:* `for suite in ${SUITES[@]+"${SUITES[@]}"}` — the same idiom the author already used correctly
at `lib/leadv2-mission-writeset.sh:164`.

**M3 — `lib/leadv2-mission-writeset.sh:32-117` — a "Bash 3.2 safe" library with a hard `python3`
dependency.** If `python3` is absent, `leadv2_writeset_extract_required` prints nothing, `missing` is
empty, and `_mission_writeset_guard` returns 0: the gate fails open with no signal.
*Fix:* probe once at source time and refuse (or explicitly disable with an emitted `decision` line)
rather than silently passing.

**M4 — `.gitignore:41-46` — the un-ignore is hard-coded to this task id.** The next lane that needs a
tracked fixture repeats the special case. `plugins/leadv2/scripts/tests/fixtures/` was the path the
review suggested and is already inside `LANE_WRITES`.
*Fix:* move the two specimens under `plugins/leadv2/scripts/tests/fixtures/` and drop the
`docs/handoff` negation.

## Low

**L1 — `lib/leadv2-red-proof.sh:78` — the backing-artifact rule is three independent `grep`s over a
whole file**, so a log that mentions the fix name in one place and "3 failed" in an unrelated place
satisfies it. Acceptable for a reporting-only gate; worth a comment stating the looseness is
deliberate.

**L2 — `leadv2-dispatch-product-close.sh:44` — `${HOME}/Projects/leadv2` as the fallback root** is a
machine-specific assumption repeated ten times in this file. Not introduced here, but the new line
copies it; a single `_LV2_CANONICAL` computed once would stop the tenth copy.

---

## Type-check output

No Python or TypeScript files are in the diff, so `mypy --strict` / `npx tsc --noEmit` are not
applicable:

```
$ git diff --name-only origin/main...HEAD | grep -E '\.(py|ts|tsx)$'
none — mypy/tsc not applicable
```

Shell syntax check on every changed file, raw:

```
plugins/leadv2/scripts/leadv2-dispatch-code.sh                         OK
plugins/leadv2/scripts/leadv2-dispatch-product-close.sh                OK
plugins/leadv2/scripts/lib/leadv2-mission-writeset.sh                  OK
plugins/leadv2/scripts/lib/leadv2-red-proof.sh                         OK
plugins/leadv2/scripts/tests/test-mission-writeset.sh                  OK
plugins/leadv2/scripts/tests/test-red-proof-gate.sh                    OK
tests/run-all.sh                                                       OK
```

Suite baselines under `/bin/bash` 3.2.57(1)-release: `test-mission-writeset.sh` 18/0,
`test-red-proof-gate.sh` 19/0.

## Contradiction scan

- `LEADV2_REQUIRE_MISSION_WRITESET` — declared once (`:649`), read once (`:3469`); no drift, but the
  default contradicts the round-2 instruction (see C4).
- `LEADV2_CANONICAL_ROOT` — consistent across `leadv2-dispatch-code.sh:553,1842`,
  `leadv2-dispatch-product-close.sh:44,50,63,87,96`, `leadv2-drift-guard.sh:69`,
  `leadv2-fanout.sh:59`. The two new sources at `:459,461` are the only places that skip it (C1).
- `LEADV2_CLOSE_GATE_DIR_OVERRIDE` — test-only, and it bypasses the L1 traversal validation by
  design; documented in-line, acceptable.
- `set -e` semantics — `leadv2-dispatch-code.sh:277` comments "NO -e", but `:442` sources
  `leadv2-helpers.sh:10` which sets `-euo pipefail`. The comment is wrong and it is load-bearing for
  C1. `leadv2-dispatch-product-close.sh` does not source helpers, so its guard degrades quietly
  rather than fatally — the two files genuinely behave differently here.
- Path existence — `docs/handoff/DISPATCH-CLOSE-GATE-01/round3-red/` referenced by the round-3 rules
  does not exist; `plugins/leadv2/scripts/tests/fixtures/` is declared in `LANE_WRITES` but was never
  created.

---

**VERDICT: fail** — 5 Critical, 3 High. Items 4, 6, 7 and both round-2 wins are genuinely done;
items 1, 2, 3 and 5 are not, and item 5 is now a hard dispatcher failure in every consumer repo.

DELIVERABLE_COMPLETE
