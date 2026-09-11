LABEL=critic-dispatch-dispatch-31cc27dd-review-1789097137 SESSION_ID=05b855ce-9832-4a7d-97ad-6c5a8d937f70
--- body from: docs/handoff/dispatch-dispatch-31cc27dd-review/critic.full.md ---
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=3 low=2

# Critic review — dispatch-31cc27dd (round 1, exhaustive, 5 lenses)

Diff reviewed: `.claude/cache/d4-review-retry/current.diff` (72 lines, 4 files; commits 7f8101de, ccba6b3e, 3567350d, all already at HEAD 74d9eb29).
Change: `_emit()` in `plugins/leadv2/scripts/leadv2-phase-record.sh:204-208` now prints `journal_write_failed=1 ... reason=journal_missing path=<bin>` and returns 2 when `JOURNAL_BIN` is unset or not a regular file (was: silent `return 0`). Tests: new missing-journal case in `test-lib-fails-closed.sh`, axis suite switched from `/dev/null` to an exit-0 stub, two `mktemp` templates.

## Evidence run (falsification lens)

Ran on head (worktree, sandbox):

| suite | result |
|---|---|
| test-phase-record.sh | pass=12 fail=0 |
| test-phase-record-worktree-axis.sh | 14 passed, 0 failed |
| test-lib-fails-closed.sh | 24 passed, 0 failed (new missing-journal case green) |
| test-gate1-discipline.sh | pass=4 fail=11 on head AND on base 7f8101de^ (git archive to /tmp) — sandbox `mkdtemp ... Operation not permitted` on bare `mktemp -d`; not attributable to this diff |

The base run of gate1-discipline also shows why the `mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX"` change exists: bare `mktemp -d` is refused in this sandbox while the templated form succeeds. Justified, though the commit body says nothing.

## Medium

**M1 — test-phase-record.sh:22 still pins the journal to `/dev/null` and calls it "silent" (tests-can-fail / contract).**
`[[ -f /dev/null ]]` is false (probed: prints `false`), so after this diff every one of the 12 `record` calls in that suite takes the new missing-journal branch and prints `journal_write_failed ... reason=journal_missing path=/dev/null` plus `journal_events_missed=1`. The suite stays green only because every call is `2>/dev/null`. Consequence: the suite no longer exercises the success-path journal write at all, and the inline comment `# silent — no real journal` is now false. The axis suite got the stub fix; this sibling did not (census: the diff touched this file for `mktemp` only, one line above).
Fix: same exit-0 stub as `test-phase-record-worktree-axis.sh:53-56`, and delete the "silent" comment.

**M2 — Product-invariant: the "surfaced" line is muted on every live caller.**
All production `record` invocations redirect stderr away and swallow rc: `leadv2-dispatch-product-close.sh:3429,3621,3704,4249`, `leadv2-phase8-close.sh:304`, `leadv2-dispatch-code.sh:9009,9058,9816,9909,10460`, `leadv2-gate1-prompt.sh:179,183-186` — all `2>/dev/null || true` or `>/dev/null 2>&1 || true`. Only `leadv2-dispatch-code.sh:5172` (`assert`, `2>&1` into `assert_out`) keeps stderr, and it only pattern-matches `admitted=bootstrap`. So the commit title "surface missing journal writes" holds for direct CLI use and the new test, not for any dispatch path. The `_EMIT_MISS` counter and summary are likewise discarded. Not a defect inside the diff; it is an overclaim about outcome. Fix (follow-up, outside this diff): either let callers keep stderr, or have `_emit` also append the miss to the ledger/journal fallback so a missing journal binary leaves a trace somewhere a lead reads.

**M3 — Census: test-gate1-discipline.sh:33 copies phase-record.sh alone into `$TMP/scripts` with no `leadv2-journal.sh` beside it.**
Same fixture shape as the axis suite before this diff: `JOURNAL_BIN` resolves to `$TMP/scripts/leadv2-journal.sh`, absent, so every `record` inside gate1-prompt now takes the loud branch. Harmless today because `leadv2-gate1-prompt.sh:179-186` mutes stderr, and unfalsifiable here (suite red on base and head for the sandbox reason above). Flagging because the diff's own removed comment named "hermetic fixtures that have no journal bin" as the reason the skip existed; two such fixtures remain (this one and M1).

## Low

**L1 — test-lib-fails-closed.sh:293 and :303 — `*'journal_events_missed=1'*` is a substring match; `=10`..`=19` also pass.**
Census: 2 instances (new line 293 copies the existing 303 shape). Anchor with a trailing newline or `$'\n'` boundary.

**L2 — leadv2-phase-record.sh:204-206 — `-z "${JOURNAL_BIN}"` arm prints `path=` empty and is unreachable.**
`JOURNAL_BIN="${LEADV2_JOURNAL_BIN:-${SCRIPT_DIR}/leadv2-journal.sh}"` (line 174) never yields an empty string. Pre-existing condition, new message; cosmetic.

## Correctness lens (no finding)
- rc contract preserved: every `_emit` call site (lines 709, 718, 721, 985, 1021, 1027, 1031, 1169, 1223, 1280) uses `|| _EMIT_MISS=$((_EMIT_MISS+1))`, so `return 2` never alters `record`/`assert` rc. Test asserts `rc=0` and passes.
- `journal_events_missed=1` in the new case implies `phase_mirror_miss` is not emitted in the FX fixture (else the count would be 2); consistent with the pre-existing badjournal case that asserts the same.
- Bash 3.2 compatible; no Bash 4 features introduced.

## Claims-without-evidence lens
- The diff makes no claim about an external system or API.
- Commit messages carry no test-run evidence (UNVERIFIED by author); verified here: three touched suites green, see table.
- Removed comment claimed the skip notice broke the axis suite; the diff changes that suite to a stub, consistent.

## Contradiction scan
- env var `LEADV2_JOURNAL_BIN`: same name in script:174 and all four tests — consistent.
- Path existence: `${WORK}/missing-journal.sh` is never created in the test — intended (the case is "missing").
- Flag semantics: none changed.
Result: none.

DELIVERABLE_COMPLETE
--- body from: docs/handoff/dispatch-dispatch-31cc27dd-review/critic.full.md ---
REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=1 low=2

# Critic review — dispatch-31cc27dd (diff: .claude/cache/d4-review-retry/current.diff)

Scope: 4 files, +18/-8. Fix (7f8101de) makes `_emit` in `leadv2-phase-record.sh` loud
(`journal_write_failed=1 ... reason=journal_missing path=<bin>`, rc 2, counted into
`_EMIT_MISS`) when no journal binary resolves, instead of silently returning 0. Tests:
new case in `test-lib-fails-closed.sh` case_7; worktree-axis suite swaps
`LEADV2_JOURNAL_BIN=/dev/null` for an `exit 0` stub; two suites use a `mktemp -d` template.

## Evidence (suites run on this worktree, HEAD 74d9eb29)

| suite | result | note |
|---|---|---|
| test-lib-fails-closed.sh | 24/0 | row7 missing-journal + failing-journal both PASS |
| test-phase-record.sh | 12/0 | |
| test-phase-record-worktree-axis.sh | 14/0 | "isolated test fixture succeeds silently" PASS |
| test-phase-record-class.sh | 20/0 | |
| test-phase-gate-inversion.sh | 18/0 | |
| test-phase-gate-names-everything.sh | 8/5 | base 7f8101de~1: 5/8 → inherited (bare `mktemp -d` EPERM in this sandbox) |
| test-state-layer-silent-write.sh | 8/2 | base: same 2 fails (active_unregister) → inherited |
| test-gate1-discipline.sh | 4/11 | base: identical 11 fails → inherited; no journal_* noise in its log |

Falsification: reverting `return 2` → `return 0` removes the `journal_write_failed` line, so
the new case_7 assertion fails; the `rc=0` assertion pins the "telemetry never changes
record rc" contract (record uses `|| _EMIT_MISS=$((...))` at :1021).

## Findings

### Medium
- **M1** `plugins/leadv2/scripts/tests/test-phase-record.sh:22` — category: tests/contract.
  Still `export LEADV2_JOURNAL_BIN=/dev/null  # silent — no real journal`. After this diff
  `/dev/null` fails `-f`, so every `record` in that suite now prints
  `journal_write_failed ... reason=journal_missing` plus `journal_events_missed=N` to stderr.
  The suite stays green only because every invocation carries `2>/dev/null`; the comment is
  now false and the suite exercises the loud path without asserting it. Fix: use the same
  `exit 0` stub the worktree-axis suite adopted (census: this is the only remaining
  `JOURNAL_BIN=/dev/null` in plugins/ and tests/) and drop the "silent" comment.

### Low
- **L1** `plugins/leadv2/scripts/leadv2-phase-record.sh:205` — category: design. `path=%s`
  prints an empty `path=` when `LEADV2_JOURNAL_BIN=""` is exported. Harmless but
  indistinguishable from the unset default; consider `path=${JOURNAL_BIN:-<unset>}`.
- **L2** `plugins/leadv2/scripts/tests/test-phase-record-worktree-axis.sh:53-56` — category:
  test-coverage. The `exit 0` stub swallows every append, so the axis suite still proves no
  journal line lands (neither did `/dev/null`). Advisory; case_7 in lib-fails-closed covers
  the positive path.

## Census
- Shape "fixture without a real journal bin": `/dev/null` only at test-phase-record.sh:22 (M1).
  Fixtures that `cp` phase-record.sh without leadv2-journal.sh beside it: test-gate1-discipline.sh:33
  (inherited red, unaffected — no journal_* lines in its log), worktree-axis (fixed in diff).
- Shape "bare `mktemp -d`" in the four touched files: none remain (all templated).
- Production callers (dispatch-code :833, gate1-prompt :170, phase8-close :301,
  product-close :3426/3618/3701/4246) resolve `${SCRIPT_DIR}/leadv2-journal.sh`, present in
  the canonical tree; none captures phase-record stderr for equality, so the new lines only
  add stderr noise when the link tree is broken (the case link-tree-heal.sh documents).

## Product invariant / contract
- "Journaling is telemetry: never changes record/assert rc" — held; header comment :185-196
  already describes the loud behaviour, the deleted comment claiming silence was the stale
  one. Bash 3.2 compatible (printf only, no arrays).

## Claims-without-evidence
- Diff comments and commit messages make no external-system or API claims. none untagged.

## Contradiction scan
- env-var names: `LEADV2_JOURNAL_BIN` consistent across script and suites. Flag semantics:
  rc 2 from `_emit` is swallowed by every caller via `|| _EMIT_MISS=...` (13 call sites, same
  shape). Path existence: `${WORK}/missing-journal.sh` is never created in the suite. none.

DELIVERABLE_COMPLETE
