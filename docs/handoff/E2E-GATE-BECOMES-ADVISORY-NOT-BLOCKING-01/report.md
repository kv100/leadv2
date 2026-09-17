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
inside the branch in the lane worktree (target strings asserted present before running). The
guard suite must go red on its A1 advisory assertions. Then reverted, suite green again.

```
<CONTROL-1-RED>
<CONTROL-1-GREEN>
```

### Control 2 — review can still kill

(a) Demonstration: guard suite A2 runs a failing review (stub reviewer, `REVIEW_VERDICT: FAIL`)
against the advisory fall-through → lane ends `dead review_verdict_fail`, exit 7 (see suite output
below). (b) Mutation: inside the inline review FAIL branch, the kill is neutered (`exit 7` → `:`
after asserting the target line present) → A2 must go red (lane no longer non-landed). Reverted →
green.

```
<CONTROL-2-RED>
<CONTROL-2-GREEN>
```

## Falsification set (raw output)

`bash -n` on every changed shell file, and the repo's changed-scope runner:

```
<FALSIFICATION>
```

## Suite runs (boundary: macOS Darwin 25.6.0, this lane worktree, <COMMIT>)

```
<SUITE-RUNS>
```

## Left red / notes

- <LEFT-RED>
