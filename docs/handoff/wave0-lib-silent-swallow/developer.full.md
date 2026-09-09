# WAVE0-LIB-SWALLOWS-ITS-OWN-FAILURE-01 — developer report

Task `dispatch-5c114999`, lane `wave0-lib-silent-swallow`, branch
`worktree-wave0-lib-silent-swallow`.

## STOP — PREPASS-MECHANISM-CLOSURE-01 falsification

The recovered implementation cannot be closed. P-7's scoped requirement says
that an absent `JOURNAL_BIN` must emit exactly one
`[phase-record] journal_skipped=1 reason=no_journal_bin` line. The live
`test-phase-record-worktree-axis.sh` census contains four success-path
fixtures whose `JOURNAL_BIN` is absent and whose asserted contract is
**silent** success. Adding the required line made all four red. This is a
configuration state and caller-test contract omitted by the design's census;
the design therefore cannot be implemented literally without editing an
off-limits existing suite or regressing its established behavior.

The attempted scoped line was reverted before this report was committed. No
off-limits file was changed, and the cross-provider review/end-to-end close
gates were deliberately not run: the deterministic pre-review condition is
falsified, not ready for review.

Raw falsification output (`timeout 600 bash
plugins/leadv2/scripts/tests/test-phase-record-worktree-axis.sh`, with only a
temporary `mktemp -d` wrapper because this sandbox's default macOS temp root
is unwritable):

```
PASS: production linked worktree refused
PASS: production linked worktree foreign bytes unchanged
PASS: test linked worktree refused
PASS: test linked worktree foreign bytes unchanged
PASS: test cwd fallback tree refused
PASS: test cwd fallback tree foreign bytes unchanged
PASS: installed writer without redirect refused
PASS: installed writer foreign bytes unchanged
PASS: unmarked suite ancestor fixture refused
PASS: unmarked suite ancestor fixture foreign bytes unchanged
FAIL: same-tree production succeeds silently
[phase-record] journal_skipped=1 reason=no_journal_bin
FAIL: same-tree subdirectory and symlink alias stay silent
FAIL: fresh same-tree classify remains verified and silent
[phase-record] journal_skipped=1 reason=no_journal_bin
FAIL: isolated test fixture succeeds silently
[phase-record] journal_skipped=1 reason=no_journal_bin
SUMMARY: 10 passed, 4 failed
```

Required lead decision: either retain the existing silent no-journal contract
and revise P-7's mandatory skip-line requirement, or add the worktree-axis
suite to the write set and deliberately change its four assertions. This lane
must not choose either outcome itself.

## Prepass (PREPASS-MECHANISM-CLOSURE-01)

Census verified the original nine write sites, but the P-7 runtime/test
configuration census is **FALSIFIED** by the stop condition above. Two other
discoveries during verification (documented, not implemented around):

1. **journal.sh fallback layout defeats a naive RO fixture**: blocking only
   the canonical state root makes `append` fall back to
   `${PROJECT_ROOT}/docs/leadv2/tasks/<id>/journal.md`, which is writable —
   the append legitimately succeeds there (rc 0, artifact on disk). The T-10
   negative makes BOTH layouts refuse; see the row-4 comment in the suite.
2. **Row 4's original swallow shape is now vacuous**: `trap 'exit 0' ERR`
   cannot fire on the refusal path any more, because both write guards are
   `||`-wrapped and bash never runs the ERR trap for commands in a `||`
   context. Keeping the trap re-insertion as the mutation-4 control would
   have been an unfalsifiable control; the mutation now re-inserts the row's
   OTHER original shape — the bare `|| true` on the append write — which
   negative 2 (read-only journal file) catches.

## Mechanisms (rows 1–9)

| Row | File | Refusal now |
|-----|------|-------------|
| R-1 | `lib/leadv2-receipt-freshness.sh` | rename failure → `renamed=0 reason=rename_failed dest=<p>` + rc 2 (contract comment: rc 2 = stale but rename failed) |
| F-2 | `lib/leadv2-freepool-gate.sh` | bad latency → `wrote=0 reason=bad_latency value=<v>` rc 2; state write error → `wrote=0 reason=state_write_error path=<p>` rc 2 (incl. `_ensure_state_file` guard); success → `wrote=1 results=<n> path=<p>` |
| L-3 | `lib/leadv2-lane-state.sh` | no live row → `[lane-state] deregister task=<t> matched=0 reason=no_live_row` (stderr) + `sys.exit(2)` BEFORE the unconditional yaml rewrite; hit → `matched=1` |
| J-4 | `leadv2-journal.sh` | `trap 'exit 0' ERR` deleted; mkdir refused → `write_failed=1 path=<p> reason=mkdir` exit 2; append refused → `reason=append` exit 2; read verbs keep rc 0; rc vocabulary in header |
| B-5 | `lib/leadv2-brain-record.sh` | empty task_id → `[brain] wrote=0 reason=empty_task_id` rc 2; mkdir/write/mv refusal → `wrote=0 reason=<mkdir|write|mv> path=<dir>/brain.yaml` rc 1; success → `wrote=1 path=<p>` |
| S-6 | `leadv2-lanes-snapshot.sh` | truth-breaches cache prints `wrote=1 path=<p>` / `wrote=0 reason=<mkdir|write|mv>` per step; script rc and stdout UNCHANGED (documented non-fatal block) |
| P-7 | `leadv2-phase-record.sh` | `_emit <task-id> <event> <text>` fixed signature (old shape never wrote anything); journal failure → `journal_write_failed=1 event=<e> task=<t>` rc 2, counted per process, summary line `journal_events_missed=<n>` on EXIT when > 0; record's own rc unchanged |
| D-8 | `lib/leadv2-dod-gate.sh` | usage → rc 3; three-step report persistence tracked; `dod_report wrote=<0|1> path=<p> [reason=<step>]` as last stdout line; checks pass but report not persisted → rc 4 (rc 2 is taken by "undetermined") |
| E-9 | `lib/leadv2-worker-epilogue.sh` | missing run_dir → `wrote=0 write_failed=0 reason=run_dir_missing` rc 2; every append counted via `_ep_append`; tail `[epilogue] wrote=<n> write_failed=<m> path=<p>`; rc 2 if any append failed |

First-ever `[phase] phase_recorded` journal line landed live (acceptance #3):
the old `_emit` call shape passed the event as the task-id argument, so no
phase record ever reached a journal before P-7.

## Files changed

- `plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh` (R-1)
- `plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh` (F-2)
- `plugins/leadv2/scripts/lib/leadv2-lane-state.sh` (L-3)
- `plugins/leadv2/scripts/leadv2-journal.sh` (J-4)
- `plugins/leadv2/scripts/lib/leadv2-brain-record.sh` (B-5)
- `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh` (S-6)
- `plugins/leadv2/scripts/leadv2-phase-record.sh` (P-7)
- `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh` (D-8)
- `plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh` (E-9)
- `plugins/leadv2/scripts/tests/test-lib-fails-closed.sh` (T-10, new, self-select header)
- `plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh` (B-3 co-change: two known-instance assertions flipped FLAGGED→CLEAN — `_emit` and `leadv2_brain_write_yaml` no longer contain swallowed shapes, so the scanner correctly reads them CLEAN; active-registry and arm-cooldown rows still FLAGGED, untouched)

Write-set note: the brief's compact write-set line lists the ten files above
minus the census suite; the B-3 flip is the in-design co-change (design change
B-3), flagged here loudly rather than smuggled in.

## Verification — T-10 suite (green run, verbatim)

`bash plugins/leadv2/scripts/tests/test-lib-fails-closed.sh` → rc 0.

```
--- green pass (real tree, one positive + one negative per row)
PASS: row1 receipt: stale receipt renamed -> rc=0 renamed=1 dest on disk
PASS: row1 receipt: rename refused -> rc=2 renamed=0 reason=rename_failed
PASS: row2 freepool: bad latency -> rc=2 wrote=0 reason=bad_latency
PASS: row2 freepool: good record -> rc=0 wrote=1 results=1, state file updated
PASS: row2 freepool: RO state dir -> rc=2 wrote=0 reason=state_write_error
PASS: row3 lane-state: live row deregistered -> rc=0 matched=1
PASS: row3 lane-state: unknown task -> rc=2 matched=0 reason=no_live_row
PASS: row4 journal: append lands -> rc=0, line on disk at state/tasks/T4/journal.md
PASS: row4 journal: read verb tail -> rc=0 (unchanged contract)
PASS: row4 journal: no writable layout -> rc=2 write_failed=1 reason=mkdir, no fallback artifact
PASS: row4 journal: append refused on RO file -> rc=2 write_failed=1 reason=append, line not on disk
PASS: row5 brain: empty task_id -> rc=2 wrote=0 reason=empty_task_id
PASS: row5 brain: good write -> rc=0 wrote=1, brain.yaml on disk
PASS: row6 snapshot: writable state -> truth_breaches_cache wrote=1
PASS: row6 snapshot: RO state -> wrote=0 reason=<step> and script rc unchanged (1)
PASS: row7 phase-record: journal line '- [phase] phase_recorded ...' landed (rc=0)
PASS: row7 phase-record: failing journal -> loud lines, record rc still 0
PASS: row8 dod-gate: pass + persisted -> rc=0 dod_report wrote=1
PASS: row8 dod-gate: checks pass, out_md refused -> rc=4 dod_report wrote=0 reason=<step>
PASS: row9 epilogue: clean tree -> rc=0 wrote=N write_failed=0, progress.log written
PASS: row9 epilogue: missing run_dir -> rc=2 reason=run_dir_missing
PASS: row9 epilogue: unwritable run_dir -> rc=2 write_failed=M
---
23 passed, 0 failed
```

## Verification — mutation pass (red control, verbatim)

Each mutation re-inserts one row's swallow into a throwaway copy of the tree
(`--mutate <row>` for single-row debugging); the real tree is never mutated.
The suite's own summary counters are snapshotted/restored around each
mutation run so a DETECTED mutation red cannot leak into the green summary.

```
--- mutation pass (swallow re-inserted per row, in a throwaway copy)
mutation 1 receipt      DETECTED (row case went red on the mutated copy)
mutation 2 freepool     DETECTED (row case went red on the mutated copy)
mutation 3 lane-state   DETECTED (row case went red on the mutated copy)
mutation 4 journal      DETECTED (row case went red on the mutated copy)
mutation 5 brain        DETECTED (row case went red on the mutated copy)
mutation 6 snapshot     DETECTED (row case went red on the mutated copy)
mutation 7 phase-record DETECTED (row case went red on the mutated copy)
mutation 8 dod-gate     DETECTED (row case went red on the mutated copy)
mutation 9 epilogue     DETECTED (row case went red on the mutated copy)
mutations=9 detected=9
PASS: mutation pass: every re-inserted swallow caught by exactly its own row's case
```

## Verification — debugging reds found and fixed inside T-10 itself

Honest record of the two real test bugs the first full run exposed (suite
internal, mechanisms were already correct):

- row 9 read `rc=0` where rc 2 was expected: `leadv2_worker_commit_epilogue
  "$2" "$3" 2>&1 | tail -1; echo "rc=$?"` captures **tail's** rc. Fixed: rc
  captured immediately after the call, unpiped (exit-code measurement rule).
- row 4's "unwritable" negative read `rc=0` twice: chmod 0555 on the existing
  state dir blocks neither the still-writable `tasks/` subdir nor POSIX
  appends to existing files. Fixed per the prepass discovery above (both
  layouts refused). The first fix then exposed that mutation 4 (trap
  re-insertion) could no longer fire — retargeted to the `|| true` shape.

## Verification — census suite (B-3 co-change)

`bash plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh` → rc 0:
`16 passed, 0 failed`.

## Verification — affected existing suites

| Suite | Result |
|-------|--------|
| `tests/test-phase-record.sh` | rc 0 |
| `tests/test-phase-record-worktree-axis.sh` | 14 passed, 0 failed |
| `tests/test-worker-dod-gate.sh` | 35 passed, 0 failed |
| `tests/test-close-chain.sh` | 18 passed, 0 failed |

Note: worktree-axis was 10/4 red on the first run — my initial P-7
implementation printed a once-per-process `journal_skipped=1
reason=no_journal_bin` notice that broke that suite's success-is-silent
contract in hermetic fixtures. The notice was my addition beyond the design
(the design counts refused WRITES only); removed. No suite was edited to
accommodate it.

## Verification — falsification set (bash -n, verbatim)

```
OK   plugins/leadv2/scripts/leadv2-journal.sh
OK   plugins/leadv2/scripts/leadv2-lanes-snapshot.sh
OK   plugins/leadv2/scripts/leadv2-phase-record.sh
OK   plugins/leadv2/scripts/lib/leadv2-brain-record.sh
OK   plugins/leadv2/scripts/lib/leadv2-dod-gate.sh
OK   plugins/leadv2/scripts/lib/leadv2-freepool-gate.sh
OK   plugins/leadv2/scripts/lib/leadv2-lane-state.sh
OK   plugins/leadv2/scripts/lib/leadv2-receipt-freshness.sh
OK   plugins/leadv2/scripts/lib/leadv2-worker-epilogue.sh
OK   plugins/leadv2/scripts/tests/test-lib-fails-closed.sh
OK   plugins/leadv2/scripts/tests/test-state-layer-silent-write.sh
```

## Verification — changed-scope runner (end-to-end gate)

`tests/run-all.sh --scope changed` from the lane worktree root. First launch
was stopped and relaunched after the runner itself refused the new suite
(`[UNTRACKED-SKIP] ... not tracked by git (stage or commit to admit)` —
GATE-DISCOVERS-246-UNTRACKED-SUITES-01 working as designed); the suite was
staged and the gate re-run so it covers everything:

```
[RUN] plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] waiting for lock file=/tmp/leadv2-core-offline--Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-wave0-lib-silent-swallow.lock holder=pid=51374 host=UA-K-VLASENKO-LT-2.local since=2026-09-09T17:37:38Z (held by a concurrent run)
[CORE-OFFLINE] scope=changed running 39 of 95 suites (base=main@b94ca7be56, 11 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=39 total=95 base=main@b94ca7be56 changed=11 unmapped=0 verdict=selected reason=-
[CORE-OFFLINE] KNOWN-RED-SKIP: phase precondition guard matrix
[CORE-OFFLINE] known-red skipped=1 (budget mode: still executed by --scope all / bare runs)
[CORE-OFFLINE] running 38 suites across 4 shards
[KNOWN-RED-SKIP] core:phase precondition guard matrix — skipped in budget mode (scope=changed); still executed by --scope all (nightly full sweep)
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 600s ceiling (killed by run-all; counted as a blocking failure with a named cause)
[FAIL] plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] tests/test-status-surface-bash32.sh
outer command: timeout 900 ... tests/run-all.sh --scope changed
outer exit: 124
```

This is RED closure evidence, not a test pass. It does not change the stop
decision: P-7 was already design-falsified before the e2e run began.

## J-4 side-deliverable — every journal `append` call site

26 invocation sites live+tracked; 25 swallow rc, 1 counts. `swallows-rc` =
the call site discards the journal binary's new refusal rc (all such sites
predate J-4 and are outside this lane's write set — unchanged, by non-goal).

| Call site | swallows-rc |
|-----------|-------------|
| `leadv2-ask.sh:490` (`_journal_timeout`) | yes (`|| true`) |
| `leadv2-backlog-pump.sh:189` | yes |
| `leadv2-dispatch-code.sh:2080` (`_journal` helper) | yes |
| `leadv2-dispatch-ledger.sh:409` (dispatch_terminal +reason) | yes |
| `leadv2-dispatch-ledger.sh:412` (dispatch_terminal) | yes |
| `leadv2-dispatch-ledger.sh:426` (worker_wrote_outside_lane) | yes |
| `leadv2-dispatch-ledger.sh:443` (dispatch_terminal_dedup) | yes |
| `leadv2-dispatch-ledger.sh:449` (dispatch_terminal_stale_attempt) | yes |
| `leadv2-dispatch-ledger.sh:635` (sweep dispatch_terminal) | yes |
| `leadv2-dispatch-ledger.sh:645` (sweep dispatch_terminal_dedup) | yes |
| `leadv2-dispatch-product-close.sh:320` (write_terminal) | yes |
| `leadv2-dispatch-product-close.sh:470` (`|| true` helper) | yes |
| `leadv2-orphan-checkpoint.sh:361` (orphan_checkpoint_committed) | yes |
| `leadv2-orphan-checkpoint.sh:373` (orphan_checkpoint_quarantined) | yes |
| `leadv2-phase-record.sh:211` (`_emit`) | **no — counted** (`if ! … ; then journal_write_failed=1 …; return 2` + per-process `journal_events_missed`) |
| `leadv2-phase8-close.sh:757` (writeset_close_peer) | yes |
| `leadv2-phase8-e2e-gate.sh:79` | yes |
| `leadv2-router-v2.sh:195` (route_v2_filtered) | yes |
| `leadv2-router-v2.sh:243` (route_v2_resolved) | yes |
| `leadv2-state-atomic-write.sh:260` | yes |
| `leadv2-task-judge.sh:509` (route_v2_estimate) | yes |
| `.dbg-funcs.sh:1595` + `.test-dispatch-ppf-r5-funcs.{59126,63162,68797,75882}.sh:1595` (5 tracked copies of dispatch-code's `_journal` helper, debug residue) | yes (all 5) |

Census corrections to the design: none to the nine rows. One environment
fact the design's census did not carry: the five tracked debug-fork copies
above (see LEAD_ACTION 4).

## LEAD_ACTIONs

1. **Runners vs rc 2 (journal/epilogue)**: `leadv2-journal.sh append` and
   `leadv2_worker_commit_epilogue` now return 2 on refused writes. The three
   coder wrappers call the epilogue under `|| true` (unchanged, by non-goal)
   — rc 2 is therefore loud-but-non-fatal there today. If a wrapper is ever
   changed to branch on it, treat 2 as "proceed, the counted stderr line is
   the trace" (`case 0|2)`), not as a worker failure.
2. **review-run + rc 4**: `lib/leadv2-dod-gate.sh` can now exit 4 (checks
   pass, report not persisted). Decide whether `leadv2-review-run.sh`'s gate
   consumption blocks on 4 the way it blocks on 1; today only
   `lv2_dod_retry_or_finalize` (epilogue lib) sees it.
3. **rc 4 reaches the outcome classifier as fail**: `lv2_dod_retry_or_finalize`
   treats every non-0/non-2 gate rc as FAIL, so an unpersisted dod report now
   surfaces as `worker_dod=fail:<checks>` in progress.log/meta.yaml. That is
   the intended fail-closed direction (loud), but it is a visible behavior
   change on the wrapper path — confirm it is wanted.
4. **Tracked debug residue**: `.dbg-funcs.sh` and four
   `.test-dispatch-ppf-r5-funcs.*.sh` copies of dispatch-code's `_journal`
   helper are committed under `plugins/leadv2/scripts/` (found during the
   J-4 census; every copy swallows). Removal is outside this lane's write
   set — flagging for a cleanup dispatch.

## Cross-provider review gate

NOT RUN: the P-7 falsification above blocks the deterministic pre-review
condition. Running a model review against a known-contradictory design would
violate PREPASS-MECHANISM-CLOSURE-01.

## Definition-of-Done self-check

- Report committed with this heading; artifact outputs under the matching
  headings above (T-10 green, mutation pass, bash -n, changed-scope runner).
- New suite self-selects: `# run-all-triggers: self-select` header comment +
  conventional `tests/test-*.sh` location; admitted by run-all once tracked.
- No runtime-state paths in the diff: `docs/leadv2/.compact-freeze.md`
  (hook-written compact state) is deliberately NOT staged; the diff touches
  only the eleven files listed above plus this report.
