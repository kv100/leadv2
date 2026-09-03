# Five-day sweep — merged verdict, 2026-09-03

Three independent audits of the work done on the leadv2 plugin between 2026-08-29 and 2026-09-03,
run in parallel, each with its own method. This file is the single table the state-owner task
(`CONTROL-PLANE-HAS-NO-OWNER-01`) is gated on: **every row that is not clean carries either a
backlog task id or a written reason for not fixing it.**

Sources: `audit1-merges.md` (84 merges), `audit2-worktrees.md` (145 worktrees),
`audit3-reports.md` (30 handoff reports).

## What the three audits found

| audit | scope | clean | not clean |
|---|---|---|---|
| 1 — merges | ~35 distinct features across 84 merge commits | 32 LIVE | **3 DEAD** |
| 2 — worktrees | 145 worktrees, 90 unmerged real commits | 115 carried no real work; 15 already landed or superseded | **11 worth merging, 4 need a decision** |
| 3 — reports | 30 handoff reports vs. the live tree | 27 HOLDS, 0 BROKEN | **3 UNTESTABLE** |

Audit 1's headline is worth stating plainly: **32 of 35 features are live mostly by luck of shape** —
they patch files that were already wired (`leadv2-dispatch-code.sh`, `leadv2-review-run.sh`,
`hooks.json`), so wiring came for free. All three DEAD entries are the opposite shape: a **new
standalone script** nobody calls. That is the pattern to watch, not a per-feature accident.

## Every not-clean row and its disposition

| # | finding | source | disposition |
|---|---|---|---|
| 1 | `leadv2-hook-fork-guard.sh` shipped with zero production callers | audit 1 | **HOOKS-PARITY-ACROSS-REPOS-01** — live lane, deliverable #1 is wiring it so it fires without anyone invoking it |
| 2 | `leadv2-hook-fork-budget.sh` shipped with zero production callers | audit 1 | **FORK-BUDGET-IS-DEAD-01** (new, p97) — wire it or delete it with its test |
| 3 | CI-RUNS-THE-SUITES-01 claimed "CI runs the suites"; GitHub had never executed it once | audit 1 | Pushed 2026-09-02 (`258d018e..c44de765`); the first run then failed on a macOS-only `mktemp` form → **CI-SUITES-ARE-MACOS-ONLY-01** (new, p99). Required status checks stay off until it is green — **SD-CI-REQUIRE-STATUS-CHECKS-01** |
| 4 | 11 worktrees hold real work that never reached `main` (90 commits) | audit 2 | **SALVAGE-UNMERGED-LANES-01** (new, p98) — each merged after its own suites run, or explicitly rejected |
| 5 | 4 worktrees need a call before merge or discard (`6409fada`, `OPS-42`, `PHASE-BOOTSTRAP-ADMIT-02`, `ANTI-SILENCE-BEAT-ABORT-03`) | audit 2 | same task, named explicitly in its scope |
| 6 | 3 reports assert pasted pass counts as evidence without a live re-run | audit 3 | **REPORT-PASS-COUNTS-ARE-ASSERTED-01** (new, p96) |
| 7 | 115 of 145 worktrees carry no work at all | audit 2 | **Not fixing.** Cleanup is already governed by `SD-SYMLINK-FARM-CONVERT-01`, whose own condition is "no live lane". Pruning worktrees while lanes run has already killed two live lanes once; the cost of leaving them is disk, the cost of sweeping them is lost work |
| 8 | `FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01`'s report names `scripts/leadv2-worker-output-gate.sh`; the file is at `scripts/lib/` | audit 3 | **Not fixing.** A wrong path in prose, the claim itself holds. Recorded here so a future reader is not sent hunting |

## What this does not cover

Audit 3 read reports against the live tree; it did not re-execute suites. Its own weakest sentence
is the honest one: a pasted "18 passed, 0 failed" is a claim, not evidence. Row 6 exists because of
that, and until it closes, treat every pass count in a five-day-old report as unverified.
