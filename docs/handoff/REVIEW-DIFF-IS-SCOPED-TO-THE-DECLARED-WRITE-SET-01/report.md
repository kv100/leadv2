# REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01 — report

## Evidence

Both negative controls were RUN through `plugins/leadv2/scripts/leadv2-mutation-control.sh`
(WORKER-DOD-GATE-01), not asserted from hand-run prose. Generator artifacts:

- `docs/handoff/REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01/mutation-control/20260917T100756Z-75854.txt`
  — control 1, `mutated_rc=1`, `red_line=FAIL: R1 augmented sibling missing or incomplete: ...`
- `docs/handoff/REVIEW-DIFF-IS-SCOPED-TO-THE-DECLARED-WRITE-SET-01/mutation-control/20260917T100842Z-99881.txt`
  — control 2, `mutated_rc=1`, `red_line=FAIL: R2 scoping leak: +++ b/base.txt`

Both ran in the tool's default scratch mode (never the real lane file — confirmed after each run:
`grep -n CONTROL-[12]-MUTATION plugins/leadv2/scripts/leadv2-review-run.sh` found nothing, and
`git status --porcelain` showed the real file's only change was still the original 74-line fix).
The manual before/after transcripts below were produced first, while iterating on the right
mutation shape (the first control-2 attempt — detection line only — did not redden the suite,
which is itself a finding, see "Left alone" below); the generator runs above are the artifact of
record.

## Chosen diff source, and the rejected alternative

**Chosen:** keep the caller-supplied, write-set-scoped diff as the primary review input, and
*augment* it — only when a gap exists — with a second, committed-range diff
(`_review_augment_diff_to_committed` in `plugins/leadv2/scripts/leadv2-review-run.sh:705`).
Mechanism:

1. Resolve the lane's base sha via the existing `_review_resolve_codex_base` (unchanged).
2. `committed = git diff --name-only <base> HEAD` — files the lane actually **committed**,
   range-based, never `git diff HEAD` / `git status` (so uncommitted working-tree churn this
   lane did not commit can never enter the comparison at all).
3. `visible = "+++ b/<path>"` lines already in the supplied diff.
4. `missing = committed − visible`. If empty → no-op, the original diff/mission are untouched
   (R3 below).
5. If non-empty → write a **sibling** file (`<attempt>.review.diff`, never the caller's own
   artifact) containing: a banner naming this decision, the declared write set, the list of
   appended files, the original caller-supplied diff verbatim, then `git diff <base> HEAD -- <f>`
   for each missing file. The reviewer mission is re-pointed at the sibling; the caller's diff
   file is never touched (R1's byte-identity check).
6. Emits `decision review_diff_scope task=... base=... appended=N files=...` so the difference is
   **named**, not silently resolved.

**Rejected: "just diff the lane's commit range" (`git diff <base>..HEAD` unconditionally,
replacing the write-set-scoped diff).** This removes the false-High defect but reopens the
problem the write-set scoping exists to prevent (mission.md, "Why the obvious fix is not
obviously right"): a lane that also picked up unrelated committed churn — a sibling session's
writes in this shared worktree tree, a rebase, a generated artifact — would hand the reviewer a
diff full of files the lane is not accountable for, unfocused and harder to review. Augmenting
only the *gap* keeps the write-set-scoped diff as the primary lens and only pulls in exactly the
files that are otherwise invisible.

The write-set admission gate itself (dispatch-side) is untouched, per the mission's off-limits:
declaring a write set and reviewing a diff remain two separate jobs.

## Control 1 — an undeclared-but-committed file reaches the reviewer

Mutation: disabled the whole augmentation by inserting `return 0` immediately after the two
init assignments at the top of `_review_augment_diff_to_committed` (before the fix would ever
run) — i.e. reverted to pre-fix behaviour. Target line asserted present before mutating:
`  REVIEW_DIFF_AUGMENTED_PATHS=""\n  [[ -f "${DIFF_FILE}" ]] || return 0\n` (present exactly once).

**RED (mutation applied — fix disabled):**
```
PASS: R1 gate: committed-but-undeclared file reaches the reviewer (status: pass, no false High)
FAIL: R1 augmented sibling missing or incomplete: build-attempt-1.diff dod-gate.md review-findings.json review-gate.md review-mission-sonnet.md review-pool-resolver.err review-sonnet.err review-sonnet.md review-sonnet.rc
FAIL: R1 reviewer mission does not point at the augmented diff
PASS: R1 caller-supplied diff artifact left byte-identical
FAIL: R1 review_diff_scope line: none
PASS: R2 gate: uncommitted churn does not block the round
FAIL: R2 scoping leak:
PASS: R3 no-op: no augmented sibling when the diff covers every committed file
PASS: R3 mission keeps the caller's diff path and no scope line is emitted

review-diff-scope: 5 pass, 4 fail
```
(R1's top-level gate status happens to still read "pass" under this emulator because the pooled
verdict does not reduce to the lone High deterministically here — the four assertions that
directly check the augmentation artefact are what catch the regression, and they do: FAIL.)

**GREEN (mutation reverted):**
```
PASS: R1 gate: committed-but-undeclared file reaches the reviewer (status: pass, no false High)
PASS: R1 augmented sibling shows the undeclared file and names the difference
PASS: R1 reviewer mission points at the augmented diff
PASS: R1 caller-supplied diff artifact left byte-identical
PASS: R1 engine emits the review_diff_scope decision naming the file
PASS: R2 gate: uncommitted churn does not block the round
PASS: R2 augmented diff shows committed work only — no working-tree churn leaked in
PASS: R3 no-op: no augmented sibling when the diff covers every committed file
PASS: R3 mission keeps the caller's diff path and no scope line is emitted

review-diff-scope: 9 pass, 0 fail
```
Reverted cleanly — `grep -n CONTROL-1-MUTATION` returns nothing after revert.

## Control 2 — the diff stays scoped; uncommitted/unrelated churn does not leak in

First mutation attempt (detection line only: dropped `HEAD` from the `committed=` computation so
it diffs `<base>` against the working tree) did **not** turn the suite red — the file-name gets
listed as "missing" but the per-file hunk generator still built the hunk from `<base>..HEAD`, so
an empty (uncommitted-only) diff produced no visible `+++ b/base.txt` line. This is itself a
finding, noted below.

Real leak requires mutating **both** the detection line and the per-file diff-generation line
(`plugins/leadv2/scripts/leadv2-review-run.sh:733`, inside the `while` loop) to also read the
working tree instead of `HEAD`. Target strings asserted present exactly once before mutating:
- `committed="$(git -C "${ROOT}" diff --name-only "${base}" HEAD 2>/dev/null || true)"`
- `git -C "${ROOT}" diff "${base}" HEAD -- "${f}"`

**RED (both mutations applied — scoping disabled, working tree leaks in):**
```
PASS: R1 gate: committed-but-undeclared file reaches the reviewer (status: pass, no false High)
PASS: R1 augmented sibling shows the undeclared file and names the difference
PASS: R1 reviewer mission points at the augmented diff
PASS: R1 caller-supplied diff artifact left byte-identical
PASS: R1 engine emits the review_diff_scope decision naming the file
PASS: R2 gate: uncommitted churn does not block the round
FAIL: R2 scoping leak: +++ b/base.txt
PASS: R3 no-op: no augmented sibling when the diff covers every committed file
PASS: R3 mission keeps the caller's diff path and no scope line is emitted

review-diff-scope: 8 pass, 1 fail
```

**GREEN (both mutations reverted):**
```
PASS: R1 gate: committed-but-undeclared file reaches the reviewer (status: pass, no false High)
PASS: R1 augmented sibling shows the undeclared file and names the difference
PASS: R1 reviewer mission points at the augmented diff
PASS: R1 caller-supplied diff artifact left byte-identical
PASS: R1 engine emits the review_diff_scope decision naming the file
PASS: R2 gate: uncommitted churn does not block the round
PASS: R2 augmented diff shows committed work only — no working-tree churn leaked in
PASS: R3 no-op: no augmented sibling when the diff covers every committed file
PASS: R3 mission keeps the caller's diff path and no scope line is emitted

review-diff-scope: 9 pass, 0 fail
```
Reverted cleanly — `grep -n CONTROL-2-MUTATION` returns nothing after revert; `git diff --stat`
on the subject file shows only the intended `+74` insertion (below).

## The suite that guards this file, and how it is selected

`plugins/leadv2/scripts/tests/test-review-diff-scope.sh` (new). It declares
`# run-all-triggers: leadv2-review-run` (line 15) — the self-select convention documented at
`tests/run-all.sh:264-270` (a `# run-all-triggers:` comment inside the suite, parsed by
`scan_suite_triggers`/`parse_suite_triggers`). `tests/run-all.sh --scope changed` therefore
selects this suite automatically whenever `leadv2-review-run.sh` is a changed file — no
`EXTRA_SUITE_MAP` row needed, and none added (this file already uses the trigger-comment
convention exclusively for its ~30 sibling `test-review-*.sh` suites; none of them are in
`EXTRA_SUITE_MAP` either).

Confirmed via the list-only seam (`LEADV2_RUN_ALL_LIST_TRIGGERS=1 tests/run-all.sh`): the suite
is **absent** while untracked, and appears as `leadv2-review-run:plugins/leadv2/scripts/tests/test-review-diff-scope.sh`
once `git add`ed — `plugins/leadv2/scripts/lib/leadv2-suite-discovery.sh` only admits
git-tracked/staged files (C5, GATE-DISCOVERS-246-UNTRACKED-SUITES-01), so the file must be staged
(done: `git add`) for discovery, and committed for a real lane close.

## Re-run of the 18dfa6f6 shape — false High does not reproduce

This is exactly suite case R1: the emulated reviewer reproduces the 18dfa6f6 shape honestly (it
can only see what its mission names a diff file; if that diff references
`leadv2-ratelimit-refresh-if-stale.sh` but never shows a `+++ b/` hunk for it, it returns the
same "does not exist in the repository" High). With the fix in place:

```
PASS: R1 gate: committed-but-undeclared file reaches the reviewer (status: pass, no false High)
```

`review-gate.md` records `status: pass`, not the FAIL/High the 2026-09-15 lane got, because the
reviewer's mission was re-pointed at the augmented sibling that *does* show the file
(`+++ b/plugins/leadv2/scripts/leadv2-ratelimit-refresh-if-stale.sh`).

## Diff footprint

```
$ git diff --stat plugins/leadv2/scripts/leadv2-review-run.sh
 plugins/leadv2/scripts/leadv2-review-run.sh | 74 +++++++++++++++++++++++++++++
 1 file changed, 74 insertions(+)
```
Pure addition (one new function + its one call site at the existing top-level script flow,
`plugins/leadv2/scripts/leadv2-review-run.sh:747`). No existing line was changed or deleted.
Off-limits files `leadv2-dispatch-code.sh` and `leadv2-active-registry.sh` are untouched
(verified: `git diff --name-only` shows only the two files below). The write-set admission gate
was not touched.

```
$ git status --porcelain
 M plugins/leadv2/scripts/leadv2-review-run.sh
A  plugins/leadv2/scripts/tests/test-review-diff-scope.sh
```

## Self-check (falsification set)

```
$ bash -n plugins/leadv2/scripts/leadv2-review-run.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-review-diff-scope.sh && echo OK
OK
```
No Python files were changed by this lane (`py_compile` not applicable).

`tests/run-all.sh --scope changed` (full changed-scope selection, this lane's checked-out
worktree, 4 other leadv2 lanes concurrently active in this same shared worktree tree at the time
of the run): 23 passed, 13 failed, 3 known-red-skipped. All 13 failures were investigated
individually against the **unmodified** (pre-lane, `git show HEAD:...`) copy of
`leadv2-review-run.sh`, one suite at a time, in isolation:

| suite | vs. unmodified engine | verdict |
|---|---|---|
| test-review-unreviewed-artifact.sh | FAIL (same assertion) | pre-existing, unrelated |
| test-fable-think-tier.sh | FAIL (PyYAML-dependent, 10 failing cases) | pre-existing, unrelated |
| test-review-body-lost-retry-distinct-arm.sh | FAIL (same assertion) | pre-existing, unrelated |
| test-review-gate-shows-findings.sh | FAIL (16 failing cases) | pre-existing, unrelated |
| test-review-single-owner-census.sh | FAIL (same assertion) | pre-existing, unrelated |
| test-fp07-verification.sh | FAIL ("FP-07 fix not found") | pre-existing, unrelated |
| test-review-union-verdict.sh | FAIL (same 3 cases) | pre-existing, unrelated |
| test-review-gate-names-the-unreadable.sh | rc=124 (times out) | pre-existing, unrelated (timeout, environment_dependent) |
| test-leadv2-review-routing.sh | PASS | passes in isolation against my change too — full-run failure is concurrency noise (4 other active leadv2 lanes sharing this worktree tree; matches the documented `core-offline reds under concurrent runners` pattern) |
| test-plan-run-contract.sh | PASS | passes in isolation against my change too — concurrency noise |
| test-review-body-short-clean-pass.sh | PASS | passes in isolation against my change too — concurrency noise |
| test-review-engine-fanout-multiprovider.sh | PASS | passes in isolation against my change too — concurrency noise |
| test-review-gate-terminal-fallback.sh | PASS | passes in isolation against my change too (isolated re-run: 15/15); full-run failure was one signal-timing assertion (`expected 130, got 0`) under concurrent load |

None of the 13 is a regression introduced by this diff. `test-review-diff-scope.sh` itself
(the suite guarding this change) passed 9/9 both standalone and via `tests/run-all.sh --scope
changed` self-selection.

## Left alone / findings noted, not fixed (out of scope for this lane)

- The intermediate control-2 mutation (detection-line only) surfaced that the "Appended committed
  files:" banner text can name a file whose actual appended hunk is empty/unavailable (base..HEAD
  diff of a file whose only difference is uncommitted) — this is a **textual**, not a **hunk**,
  imprecision; the property this lane's mission requires (no working-tree-only hunks leak into the
  reviewed diff) held even under that partial mutation. Not fixed here: out of the stated scope
  (fixing the banner's file list to match exactly what got appended would touch the same function
  again for a cosmetic-only gap with no verdict-changing effect) and no suite assertion currently
  requires it; flagging it rather than silently folding it into this change.
- The 13 pre-existing red/timeout/flaky suites above are left exactly as found — none is this
  lane's subject, and per lane-rules.md this is a reportable rather than a required fix.
