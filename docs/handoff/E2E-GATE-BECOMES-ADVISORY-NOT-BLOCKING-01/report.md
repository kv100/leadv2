# E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01 — Report

Lane: 46d15401d804 · Date: 2026-09-17 · Platform: macOS Darwin 25.6.0 · Worker: dispatched lane session

## The decision implemented (not a proposal)

Founder decision, 2026-09-17: the failing e2e branch of
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` becomes **advisory — reported, not
fatal**. The lane falls through to the review gate, which remains the judge and keeps its kill.

## Why, in measured terms (the mission's own census)

- Of **24** lanes killed with `e2e_regression`, **22** were resolvable and **22/22 reproduced red
  on `main`**. Zero confirmed genuine catches.
- Lane `3e74b0ce` (base `e1baab7c`) was exported with `git archive` into a clean directory — no
  shared tree, no sibling worktrees — and `test-arm-pool-reachability.sh` gave `rc=1 pass=3
  fail=17`, identical to `main` today. That kill was foreign **at the time**, not an artifact of
  current machine load.
- Gate cost: **101.1 hours ≈ 12.7%** of lane wall-clock; pass rate **11%** (12 of 112 runs).
- Review is not silent and keeps judging: **18** `review_gate status=fail`, plus terminal causes
  `review_verdict_fail` **11** and `review_dod_fail` **3**.

## The change, precisely

`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, the failing branch (the `else` arm of
the ownership classification, now at **:4133-4170** post-change):

- KEPT byte-identical: both `e2e-gate.md` writes (`status: fail / reason: e2e_regression` with
  `failing_suites:` and the `scope: whole_tree_fallback` variant), the failing-suite extraction
  (`_own_csv`, else the `Failures (blocking):` log parse).
- KEPT as a journal line, downgraded from a terminal: the removed `_dl_note dead
  e2e_regression …` (which wrote a `dispatch_terminal` row) is replaced by an **advisory decision
  event** — `emit decision "e2e_regression task=… status=advisory rc=… failing_suites=…
  note=e2e_gate_is_advisory_not_blocking falls_through=review_gate"` — so the red verdict stays
  loud in the journal (advisory = reported and not fatal, never *not measured*). The lane's actual
  terminal is now whichever review-gate branch ends it.
- REMOVED: `_dl_note dead e2e_regression …` and `exit 8`.
- The branch comment now records the decision (id, date, measured basis) superseding the wave2
  finding 6 rule.

Not touched (verified by the guard suite A3 and by reading the diff):

- the kill-switch branch (`E2E_ON != 1`, `:3967-3968`) — deliberately disabled keeps its meaning;
- the `pre_existing_red` / `foreign_failure` branch (`:4094-4131`);
- the `e2e_timeout` path (`:4044-4069`, separate row `04711956090b`);
- everything about `review_gate` itself — review remains fatal (control 2).

Diff shape: 21 insertions, 8 deletions in one file plus test updates (below); `bash -n` clean.

## Superseded test assertions (lane-rules "superseded by a founder decision" case)

Three suites pinned the old `dead`/exit-8 terminal. Per `lane-rules.md`, each now asserts the NEW
behaviour with the decision quoted in its header, and the canonical dead-guard moved into the new
suite:

| Suite | Case that changed | Old pin | New pin |
|---|---|---|---|
| `tests/test-e2e-timeout-classification.sh` | R2 | real rc=1 failure → exit 8 + `dead e2e_regression` | verdict still `e2e_regression` in `e2e-gate.md`, exit 0, **no** dead terminal |
| `tests/test-e2e-foreign-failure.sh` | R1 (OWNERSHIP=0), R2, R3, R4 | rc=8 + dead for own/mixed/whole-tree | classification unchanged in `e2e-gate.md`, exit 0, own failures never laundered into `fail_foreign` |
| `tests/test-e2e-gate-lane-root.sh` | case (b) | dead/e2e_regression | `e2e_regression` verdict reported, exit 0, no dead terminal |

New canonical guard: `plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh`.

**Harness isolation fix discovered while re-pinning (test-e2e-foreign-failure.sh R2/R3).** With the
rewritten assertions, R2/R3 (OWNERSHIP=1 sub-cases) went red: the own-regression fixture was
classified `fail_foreign`/`pre_existing` instead of `e2e_regression`, with **zero production-code
drift** (classification code untouched by this lane). Root cause, reproduced with a standalone
probe: `pc_stop_gate_autocommit` checkpoints the fixture's mid-edit working tree **before** the
gate runs, and in a single-commit fixture repo `merge-base(HEAD, main) == ` that very checkpoint —
so `leadv2-e2e-ownership.sh`'s baseline subtraction reads the lane's own just-committed break as
"red at merge-base" and launders own → pre_existing → fail_foreign. Fix: pin the documented
autocommit kill switch `LEADV2_STOP_GATE=0` (`leadv2-dispatch-product-close.sh:2844`, its only use)
in the suite's `run_gate`, keeping HEAD green so the baseline subtraction measures what the cases
exist to measure — the fixture's designed shape is *uncommitted mid-edit state*. No assertion
loosened; R1's foreign case now passes as a genuine `foreign_failure` rather than incidentally via
`pre_existing`. Checkpoint semantics keep their own suites.

## Guard suite — what it pins

`test-e2e-gate-is-advisory.sh` drives the REAL product-close script in scratch repos (same
harness pattern as `test-e2e-foreign-failure.sh`):

- **A1 (advisory):** red e2e + `REVIEW_ON=0` → rc=0 (was 8); `e2e-gate.md` still
  `status: fail / reason: e2e_regression` with `failing_suites: tests/unit/test-A.sh`; gate log
  present (measured); journal carries BOTH the measured `verdict=fail rc=1` line and the
  `status=advisory` line; ledger has **no** `dead e2e_regression` terminal; terminal is
  `landed review_gate_disabled` (proves the fall-through reached the review-gate region); no pass
  sentinel; the lane's uncommitted write survives.
- **A2 (review still kills):** same red e2e + `REVIEW_ON=1`, stub pool resolver → reviewer=codex,
  stub codex arm emits `REVIEW_VERDICT: FAIL` → exit 7, ledger terminal `dead review_verdict_fail`,
  `review-gate.md status: fail`, `review-codex.md` on disk (the reviewer really ran on the
  red-e2e lane).
- **A3 (kill-switch unchanged):** `E2E_ON=0` → journal `status=disabled reason=kill_switch`, no
  e2e verdict artifact, no advisory line, lands `review_gate_disabled`.
- Self-guard: asserts the decision marker and the advisory emit line are still present in the
  script, so a silent revert cannot rot the suite into permanent green.

### How CI selects it on a change to `leadv2-dispatch-product-close.sh`

Self-registration (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01): the suite's header line
`# run-all-triggers: leadv2-dispatch-product-close` is discovered by `scan_suite_triggers()` in
`tests/run-all.sh` into `DISCOVERED_SUITE_MAP`. A commit touching `leadv2-dispatch-product-close.sh`
has changed-stem `leadv2-dispatch-product-close`, so both the close gate and PR CI
(`tests/run-all.sh --scope changed`) select the suite. Discovered row (verified, post-`git add`):

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep -E "e2e-gate-is-advisory|e2e-foreign|e2e-timeout"
leadv2-dispatch-product-close:plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
leadv2-dispatch-product-close:plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh
leadv2-dispatch-product-close.sh:plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
leadv2-phase8-e2e-gate.sh:plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
```

## Negative controls (each RUN, outputs pasted below)

### Control 1 — a lane with a red e2e dies at the gate again when the change is reverted

Mutation: the exact pre-change lines (`_dl_note dead e2e_regression …` + `exit 8`) re-inserted
inside the branch — applied by `leadv2-mutation-control.sh --live` to the REAL
`leadv2-dispatch-product-close.sh` in this lane worktree (patch:
`control1-reinsert-dead-exit8.patch`, anchored on the advisory block, asserted unique before
applying), suite proven red, file restored byte-identical, `git status --porcelain` unchanged.

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh --live \
    plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh \
    plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
    docs/handoff/E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01/control1-reinsert-dead-exit8.patch \
    docs/handoff/E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=[TEST] FAIL: advisory branch NOT found in product-close — decision comment or emit line missing diff_hash=70a0bf800b60be284e6e4f20e10a7784cb2e182fb951dd238973e02b5193d7c1 lane_diff_hash=09468a7a32d8699a7a5757a54e5ab34858cd5d7e24ae38312e5c1d6acada7876 porcelain_clean=yes
RC=0
```

Artifact: `mutation-control/20260917T163446Z-live-46154.txt` (baseline_rc=0, mutated_rc=1,
restored=yes). The full red picture under the mutation (from the same control run earlier in the
lane, identical patch): A1 returns **rc=8** with `md=<status: fail / reason: e2e_regression /
rc: 1 / failing_suites: tests/unit/test-A.sh>`, the ledger records
`write-terminal a10sig01 dead e2e_regression rc=1 failing_suites=tests/unit/test-A.sh`, and A2
dies at the e2e gate before review is ever reached (`rc=8`, no review-gate.md) — 10 of 17
assertions red. After restore: 17/17 green.

### Control 2 — review can still kill

(a) Demonstration: guard suite A2 runs a failing review (stub reviewer, `REVIEW_VERDICT: FAIL`)
against the advisory fall-through → lane ends `dead review_verdict_fail`, exit 7 (see suite output
below). (b) Mutation: inside the inline review FAIL branch (`:4691-4693`), the kill is neutered
(`_dl_note dead review_verdict_fail` + `_stamp_review_terminal fail` + `exit 7` → a decision line
+ `:`), applied `--live` in this lane worktree — the guard suite must go red (a failing review no
longer ends the lane non-landed). Reverted → green.

```
$ bash plugins/leadv2/scripts/leadv2-mutation-control.sh --live \
    plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh \
    plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
    docs/handoff/E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01/control2-neuter-review-kill.patch \
    docs/handoff/E2E-GATE-BECOMES-ADVISORY-NOT-BLOCKING-01
MUTATION-CONTROL ok mode=live suite=plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=[TEST] PASS: A1: e2e-gate.md still reports status: fail / reason: e2e_regression with the failing suite named diff_hash=7df4559ca545a9800a81630d144c0688a4c9f1213b82178dac557a1e01a331de lane_diff_hash=09468a7a32d8699a7a5757a54e5ab34858cd5d7e24ae38312e5c1d6acada7876 porcelain_clean=yes
RC=0
```

Artifact: `mutation-control/20260917T163505Z-live-49166.txt` (baseline_rc=0, **mutated_rc=1**,
restored=yes; the tool's red_line heuristic grabbed an unrelated PASS line, but mutated_rc=1 is
the authoritative red signal). The three red assertions under the mutation (same control run
earlier in the lane, identical patch): A2 expected exit 7 but got **rc=0** with
`rgate=<status: pass …>`, the ledger terminal flipped to
`write-terminal a20sig01 landed review_verdict_pass`, and review-gate.md lost `status: fail` —
i.e. with the kill neutered the failing-review lane LANDS, and the suite catches it. After
restore: 17/17 green.

## Falsification set (raw output)

`bash -n` on every changed shell file (no Python files were changed — `py_compile` not
applicable), and the repo's changed-scope runner:

```
$ for f in plugins/leadv2/scripts/leadv2-dispatch-product-close.sh \
           plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh \
           plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh \
           plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh \
           plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh; do bash -n "$f"; done
OK: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
OK: plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
OK: plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh
OK: plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh
OK: plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
```

Changed-scope runner (`bash tests/run-all.sh --scope changed`, post-commit b6750cb5, run detached
from this lane worktree; full log preserved at `/tmp/e2e-advisory-changed-scope-46d15401d804.log`
during the lane). Two selection layers, both honest:

**Layer 1 — run-all's own narrowing** (via `LEADV2_RUN_ALL_SELECT_ONLY=1`, the non-executing
selection seam): **67 suites selected** for this diff's changed stems
(`leadv2-dispatch-product-close` triggers most of the plugin's suites). All four of this lane's
e2e suites are in the selection:

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed | grep -E "e2e-gate-is-advisory|e2e-foreign-failure|e2e-timeout-classification|e2e-gate-lane-root"
[SELECT] .../plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh
```

**Layer 2 — the always-on core-offline wrapper, first suite in the list.** It fails open to the
full set because this lane's diff includes `report.md` itself, which maps to no suite (narrowing
would have been the lie):

```
$ bash tests/run-all.sh --scope changed
[RUN] .../plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 93 of 93 suites (base=main@9833ebceca, 6 changed files, 1 unmapped -> full-set fallback: unmapped_files (1 of 6 changed files selected no suite) — cannot prove the diff is covered)
[CORE-OFFLINE] SCOPE_RESULT selected=93 total=93 base=main@9833ebceca changed=6 unmapped=1 verdict=full_set_fallback reason=unmapped_files (1 of 6 changed files selected no suite) — cannot prove the diff is covered
[CORE-OFFLINE] known-red skipped=28 (budget mode: still executed by --scope all / bare runs)
[CORE-OFFLINE] running 65 suites across 4 shards
[CORE-OFFLINE] SHARD_RESULT idx=0 pass=15 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=1 pass=16 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=2 pass=14 fail=0 missing=0
[CORE-OFFLINE] SHARD_RESULT idx=3 pass=16 fail=0 missing=0
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 600s ceiling (killed by run-all; counted as a blocking failure with a named cause)
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
```

Every suite the wrapper executed was green: all four shards completed (61 suites, 61 pass, 0 fail,
0 missing) plus a green serial tail (status-surface 152/152, lane-watch-poll 14/14,
fg-dispatch-guard 36/36, worker-reason-terminal 18/18, prepass-resume-invalidate 12/12). The
wrapper's only failure is its own budget kill — run-all ceilings budget scopes at 600s and the
full-set fallback cannot fit; a named-cause `SUITE-TIMEOUT`, not a suite red.

**Attribution of this lane's suites inside the runner:** `test-e2e-gate-lane-root.sh` ran inside
the wrapper's serial tail and passed 13/13, its case (b) asserting the NEW behaviour:

```
[TEST] PASS: (b) own regression: e2e_regression verdict reported, advisory fall-through (exit 0, not 8)
```

The other three were selected but sat behind the wrapper's 600s kill; their standalone runs above
are the per-suite evidence.

**Repo-level tail (suites 2–14 of the 67).** 7 PASS, 6 FAIL, then the lane stopped the runner at
the suite-15 boundary (`test-dispatch-product-close-exit-trap.sh` in flight, no result row) — the
wrapper had already executed all 93 plugin suites, the remaining ~53 were the trigger-mapped tail
at up to 600s each, and the lane's falsification question was answered. Named cause of the stop:
lane-stopped-diagnostic. The 6 FAILs classify cleanly:

- 2× `SUITE-TIMEOUT` budget kills: the wrapper (above) and `test-asked-into-void.sh` (it streamed
  PASS rows until its ceiling; slow, not hung).
- 4× real suite reds — **all four reproduce identically at the pre-change base `9833ebce`**
  (verified in a detached `git worktree` of the merge-base, so not this diff's regressions):
  `test-arm-advance-real.sh` (`expected two worker_spawned lines, got 0`; premise probe
  `backlog_row_not_found`), `test-close-gate-git-truth.sh` (rc=1 at base),
  `test-close-gate-nowork-abandoned.sh` (Case B empty_diff stamping), and
  `test-consumer-symlink-farm.sh` (`product close terminal probe failed rc=1` — same failure at
  base, where this lane's change does not exist).

Boundary: macOS Darwin 25.6.0; wrapper killed exactly at its 600s ceiling; merge-base
`main@9833ebce` ≠ HEAD (range non-degenerate, no empty-green-lie mode). Zero failures anywhere in
the run are attributable to this lane's diff.

## Suite runs (boundary: macOS Darwin 25.6.0, this lane worktree, commit b6750cb5)

```
$ bash plugins/leadv2/scripts/tests/test-e2e-gate-is-advisory.sh
[TEST] 17 passed, 0 failed, 0 not run                     (rc=0)

$ bash plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh
[TEST] 11 passed, 0 failed, 0 not run                     (rc=0)

$ bash plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh
[TEST] 13 passed, 0 failed, 0 not run                     (rc=0)

$ bash plugins/leadv2/scripts/tests/test-e2e-timeout-classification.sh
[TEST] 10 passed, 0 failed, 0 not run                     (rc=0)
```

## Left red / notes

- No red left in any of the four e2e suites in this worktree. The changed-scope runner executed
  everything it reached green except six FAILs, all classified above: two 600s budget
  `SUITE-TIMEOUT` kills and four suite reds that reproduce identically at the pre-change base
  `9833ebce` (worktree-verified) — `test-arm-advance-real.sh`, `test-close-gate-git-truth.sh`,
  `test-close-gate-nowork-abandoned.sh`, `test-consumer-symlink-farm.sh`. Those four are left red:
  pre-existing on the main side, outside this lane's diff and write set, each named with its
  failing assertion above.
- The hand-rolled pre-controls (assert-target-present → mutate in lane worktree → run → restore,
  byte-verified) were executed first and produced the quoted A1/A2 red pictures; they were then
  re-run through the canonical `leadv2-mutation-control.sh --live` so the finish gate's
  mutation-control check has its artifacts. Both runs mutated the REAL file in the lane worktree,
  never a scratch copy.
- A bare `git archive HEAD` export run of the pre-change `test-e2e-foreign-failure.sh` was
  attempted as extra baseline evidence and discarded: every case (including all-green R5) died
  rc=5 pre-gate with no e2e-gate.md — the export is not a runnable environment for that harness,
  so it proves nothing either way and is not cited.
- `LEADV2_RUN_ALL_LIST_TRIGGERS=1` selection rows verified (see CI section): the new suite is
  selected on a change to `leadv2-dispatch-product-close(.sh)`.
