# BUILDER-SELFCHECK-GATE-01 — architect prepass (r7 narrow finisher, lane 9c027877)

Scope: design only. No implementation performed here.

## 0. Ground truth established (verified, this run)

| Fact | Probe |
|---|---|
| Lane worktree alive at `.claude/worktrees/9c027877`, HEAD `7ffe67c` (merge of main) over `f2cc0bc` | `git -C <wt> log --oneline -3` |
| Exactly one uncommitted code edit on the lane | `git -C <wt> status --porcelain` → only `M plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh` among code paths (rest is `docs/leadv2/*` lane bookkeeping + untracked handoff dirs) |
| The pending 1-line edit is `-x` → `-f` on the e2e-entrypoint probe (line ~261 of the lib) | `git -C <wt> diff -- plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh` |
| The gate block lives at `leadv2-dispatch-product-close.sh:1826-1856`, sourced at `:83-86` | `grep -n selfcheck` |
| The gate sits AFTER `pc_scope_diff` / asked-into-void, BEFORE both e2e and review | `sed -n '1805,1835p'` |
| The gate's own header claims report-only lanes "fall through unchanged (checks=0 by construction)" | same `sed` output, lines 1829-1831 |
| `test-report-only-gate.sh` case 4 asserts `review-gate.md` **byte-identical** to a `git archive HEAD` extraction; cases 1/2/3/5/6a also run red-first legs against that archive | file header, lines 4-22 |
| `test-dispatch-product-close-exit-trap.sh` sets `E2E_ON=0` **and** `REVIEW_ON=0` (args 5/6) precisely so no e2e entrypoint / git diff / review spawn is needed | file header, lines 6-8 |
| Neither the lib nor `test-builder-selfcheck-gate.sh` exists on `main` — both are lane-only, so main's copies cannot be the flake source | `ls` on main tree → MISSING |

## 1. Root-cause hypotheses (to be CONFIRMED by the implementer in step 1, not assumed)

These are derived from the code shape above, not from a suite run. The implementer runs each
suite in the foreground first and confirms/refutes before touching a line.

**H1 — the gate is not conditioned on a review arm existing (primary).**
`test-dispatch-product-close-exit-trap.sh` deliberately sets `E2E_ON=0 REVIEW_ON=0` so that the
run reaches its terminal/ledger assertions with nothing else executing. The gate's guard is
`[[ "${LEADV2_BUILDER_SELFCHECK:-1}" != 0 ]] && command -v lv2_selfcheck_run` — it consults
neither kill-switch. So in a lane where *no arm will be spent*, the gate still runs, still emits
an extra `emit decision "selfcheck ..."` row, and can still write
`review-gate.md status: blocked reason: selfcheck_failed` + `_dl_note refused` — which is a
second/contradicting terminal in a suite whose entire point is "exactly one ledger row, and it is
the TRUE intended state". The gate's stated purpose in its own comment is "before any review arm
is spent"; when no arm is spent there is nothing to protect, so running is both harmful and
purposeless.

**H2 — report-only lanes are not actually inert, contrary to the block's comment.**
The comment asserts report-only lanes fall through "checks=0 by construction". That is an
assumption about the lib's behaviour on a report diff, not an enforced condition — nothing in the
`if` tests lane kind. A report lane whose diff touches a `.sh`/`.py` file (a report *plus* an
incidental script, or a `.md` the lib's classifier mis-buckets) produces checks>0 and can return
rc=1 → `review-gate.md` becomes `reason: selfcheck_failed`, breaking case 1's
`kind: report + deliverable:` assertion and case 4's byte-identity assertion.

**H3 — red-first legs are contaminated by the gate now being in HEAD.**
`test-report-only-gate.sh` builds its "pre-fix" baseline from `git archive HEAD`. Since `f2cc0bc`
committed the gate, HEAD *contains* it — so the red-first legs no longer represent pre-change
behaviour and case 4's "byte-identical to pre-change output" can differ on both sides for a
reason unrelated to REPORT-ONLY-GATE-01. If step 1 shows the failure is only in the archive leg,
this is the cause and the fix is H1/H2 (making the gate inert on those paths), **not** editing
the suite.

**H4 — the pending `-x`→`-f` edit widens delegation reach.**
`-f` makes a non-executable `leadv2-e2e-entrypoint.sh` eligible for delegation. The call site is
`bash "${_scripts_dir}/leadv2-e2e-entrypoint.sh"`, so `-f` is the *correct* predicate (the exec
bit is irrelevant when invoked through `bash`, and a rendered/copied plugin tree can lose it).
Keep the edit. But it means fixtures that previously escaped delegation because the entrypoint
was mode 644 now delegate. It is guarded by `LEADV2_E2E_GATE="${E2E_ON}"`, so H1's fix subsumes
it — do not revert the edit as a shortcut for a red it did not cause. Audit `git diff` before
staging (mission step 5) and keep it only if step 1 confirms it is not the sole cause of a red.

**H5 — the unidentified 5th red.** Runner reported failed=5, four names printed. Identify by
name in step 1 before designing anything for it. If it lands outside the three off-limits-exempt
files, it is out of scope for this lane — report it, do not fix it.

## 2. Design — what changes

The gate must be scoped to exactly what it exists for: **proving a code diff before a review arm
is spent on a diff lane.** Two real production conditions, both already first-class concepts in
this script — neither is a test-only signal.

### Change A (primary) — gate the gate on "an arm will actually be spent"

`leadv2-dispatch-product-close.sh`, the `if` at ~:1832. Add the arm precondition:

- Run the selfcheck only when `E2E_ON` or `REVIEW_ON` indicates a downstream arm will run.
- When neither runs, skip with the existing skip vocabulary (an explicit reason field, e.g.
  `no_arm`, on the same `emit decision "selfcheck ..."` line — **not** silence, so the skip is
  auditable at the ledger).

Why this is not a bypass: it is the literal statement of the gate's charter comment. A lane with
both arms off spends nothing that the gate protects. It weakens nothing for a real lane, because
every real lane runs at least one arm — which the implementer must confirm by grepping the
dispatch call sites for how `E2E_ON`/`REVIEW_ON` are passed in production (if a real production
path can set both to 0 and still reach review, this design is wrong and must be escalated, not
worked around).

### Change B — make report-only fall-through explicit, not assumed

Same `if`. Replace the comment's assumption with an actual condition on the lane-kind signal the
script already computes (`_pc_kind` / the `LANE_DELIVERABLE` report declaration — the implementer
resolves the exact variable at the gate's line, it is in scope there since `_pc_kind` is used at
:1848). A `report:` lane skips the selfcheck and emits `selfcheck ... status=skipped
reason=report_lane`.

Why this is not a bypass: a report lane's deliverable is prose. `bash -n` on prose is a category
error; the gate has no assertion to make about it. This is the same reasoning REPORT-ONLY-GATE-01
already encodes elsewhere in the file.

### Change C — lib, keep the `-x`→`-f` edit

`lib/leadv2-builder-selfcheck.sh:261`. Keep as-is (see H4). Commit it with a message that states
why (`bash <file>` invocation makes the exec bit irrelevant; rendered plugin trees lose it).

### Explicitly rejected designs

- **A suite-only bypass env var** (`LEADV2_SELFCHECK_TEST_MODE=1` or similar) — lying-green. The
  suites would then prove nothing about the production path. FAIL by mission definition.
- **Editing the two suites to expect the new `selfcheck` decision row.** Tempting for the
  exit-trap suite, but it converts a real defect (an unconditional gate emitting terminals in
  lanes it has no business in) into an accepted behaviour. Only acceptable if step 1 proves the
  extra row is genuinely correct production behaviour AND the suite's assertion is over-tight —
  in which case say so explicitly in the deliverable with the run output as evidence.
- **Reverting `-x`→`-f`** as a red-clearing shortcut. See H4.
- **Weakening `LEADV2_BUILDER_SELFCHECK` default to 0.** Disables the whole feature.

## 3. Non-goals (implementer: ignore these entirely)

- `dispatch refusal fallback chain` and `plan-followups-01` — main-tree flakes fixed in another
  lane. Do not touch, do not investigate, do not count toward this lane's red budget.
- Any file outside the three named in `Off_limits`.
- De-duplicating `.claude/scripts/tests/` (separate open thread).
- Refactoring `lv2_selfcheck_run`'s internals, the depth guard (C1), or the degraded/checks=0
  path (M1) beyond what a confirmed red requires. If step 1 shows C1/M1 are *not* implicated,
  leave them alone — round-2 finding C3 is about the gate's *placement*, and Changes A+B are the
  placement fix.
- Adding new test cases to `test-builder-selfcheck-gate.sh` beyond whatever red-first leg is
  needed to prove A and B (one leg each is enough).

## 4. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Change A makes the gate inert on a real production lane that legitimately runs with both arms off | Before implementing, grep the dispatch call sites for the `E2E_ON`/`REVIEW_ON` argument values. If any production path passes both 0 *and* still reaches a review, escalate via `ask-lead.sh` — do not proceed. |
| Change B keys off a variable not actually in scope at :1832 | `_pc_kind` is referenced at :1848 inside the same block, so it is in scope; verify with a `bash -n` + a one-shot echo before relying on it (§6.5 unrecognized-entity rule). |
| Red-first legs of `test-builder-selfcheck-gate.sh` go vacuously green because the archive baseline now contains the gate (same trap as H3, and as commit `b9959aa`'s N1 fix) | Re-run the red-first legs and confirm each prints an actual FAIL against the baseline. A red-first leg that passes silently is a bug, not evidence. |
| Suites left backgrounded kill workers (4 lost already) | Foreground only, one suite at a time, with an explicit per-suite timeout. Never `run_in_background` a suite, never wrap a wait in a background command. |
| Fixing 4 reds but the 5th (H5) is out of the off-limits-exempt set | Report it by name with its FAIL line in the deliverable and leave it; do not widen scope. |
| A parallel session reverts the lib edit before staging | `git diff <file>` immediately before `git add`, not earlier in the turn. |

## 5. Implementation sequence (for the developer lane)

1. Foreground-run, one at a time, capturing raw FAIL lines:
   `test-dispatch-product-close-exit-trap.sh`, `test-report-only-gate.sh`,
   `test-builder-selfcheck-gate.sh`, then re-run the lane's `run-core-offline.sh` to name the 5th.
2. Confirm or refute H1/H2/H3 against those FAIL lines. Write the verdict per hypothesis.
3. Implement Change A, then Change B (separately, re-running after each — so the deliverable can
   attribute each red to the change that cleared it).
4. Audit and keep Change C (`git diff` the lib first).
5. Add one red-first leg to `test-builder-selfcheck-gate.sh` per behaviour change (skip-on-no-arm,
   skip-on-report-lane), each proven to fail against the pre-change baseline.
6. `bash -n` + `shellcheck -S warning` on all three changed files.
7. Re-run all four suites green. Commit.

## 6. Constraint checklist

1. **Env var naming** — no new env vars introduced. `LEADV2_BUILDER_SELFCHECK`, `LEADV2_E2E_GATE`
   both already exist and keep their semantics. Adding one would be the rejected lying-green
   design. PASS.
2. **File paths** — all three writable paths verified present in the lane worktree; the two suite
   paths verified; `lib/leadv2-builder-selfcheck.sh` and `tests/test-builder-selfcheck-gate.sh`
   are lane-only (absent on main) — the implementation must run in the worktree, not the main
   checkout. PASS.
3. **`claude -p` commands** — none introduced. N/A.
4. **Concurrent access** — `review-gate.md` and the ledger are written by both the gate block and
   the downstream review/e2e path. Change A removes one of the two writers on the no-arm path,
   which *reduces* the race surface. No new lock needed. The lane's `docs/leadv2/*` dirty files
   are lead-owned bookkeeping — do not stage them.
5. **Config contradiction** — the gate block's own comment at :1829-1831 currently asserts a
   report-only fall-through that the code does not implement. Change B resolves the contradiction
   by making the comment true. Flagged as a decision below.

decisions:
- D-A: gate runs only when a downstream arm will be spent — `source: architect(self-check)`, item 5.
- D-B: report-only fall-through becomes an enforced condition, not a comment — `source: architect(self-check)`, item 5.
- D-C: `-x`→`-f` retained; `bash <file>` makes the exec bit irrelevant — `source: architect`, H4.

acceptance:
  - surface: file_artifact
    observable: "In the lane worktree, docs/handoff/<fixture-task>/review-gate.md produced by the exit-trap fixture (E2E_ON=0, REVIEW_ON=0) contains no `reason: selfcheck_failed` line, and the fixture's terminal ledger file holds exactly one row naming the intended state."
    authored_at: 2026-08-20T05:51:42Z
  - surface: log_line
    observable: "Running each of test-dispatch-product-close-exit-trap.sh, test-report-only-gate.sh and test-builder-selfcheck-gate.sh in the foreground prints its own trailing all-pass summary line with a zero failure count, and the red-first legs inside test-builder-selfcheck-gate.sh each print their expected FAIL line against the pre-change baseline rather than passing silently."
    authored_at: 2026-08-20T05:51:42Z
  - surface: log_line
    observable: "The ledger decision line for a report-declared lane reads status=skipped with a report-lane reason instead of a green/degraded selfcheck verdict, so a human reading the ledger can see the gate declined rather than that it silently found nothing."
    authored_at: 2026-08-20T05:51:42Z

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-builder-selfcheck.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh
DELIVERABLE_COMPLETE
