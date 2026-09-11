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
