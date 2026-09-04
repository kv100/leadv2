# PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01 — report

## Decision: release-on-refusal (not defer-registration)

Kept the existing structure: the lane is registered BEFORE the phase gate, and the
refusal path must release it. Rationale:

1. Registration-before-guard is a deliberate prior decision (PHASES-ARE-THE-ONLY-PATH-01 §7):
   `leadv2_active_update_phase` needs a row to patch, and supervise is required to see the
   lane while it works — including while it sits in prepass. Deferring registration until
   after the gate would make the gate-refused lane invisible exactly when someone is looking
   for why nothing launched.
2. The release machinery already exists and is owner-verified (PREPASS-PROVIDER-FALLBACK-01-R5):
   the single disarmable EXIT trap (`cleanup_pending_dispatch`, leadv2-dispatch-code.sh:3505)
   releases the row on every no-worker terminal exit, including the phase refusal at ~:7133.
   The incident was NOT a missing release call — the trap ran and printed
   `active_lane_release_skipped reason=not_owner_row_intact`. The release was UNREACHABLE
   because duplicate rows for the same task_id made the python fail closed with a silent
   `exit 2` before the ownership comparison ever ran. Fixing the release path fixes the
   incident class; deferring registration would not have (a duplicate row would still block
   everything else the registry does).
3. Slot-race consequences of defer-registration (why it looked cleaner): not registering
   until the gate passes would open a window where two dispatches both think the slot is
   free (the registry row is also the cap/writeset authority — LANE-WRITESET-REGISTRY-01),
   and would need a new "pending registration" state to avoid. Releasing on refusal keeps
   the current, already-reviewed admission semantics.

## Root cause (measured)

The release python (`_release_registered_lane`, leadv2-dispatch-code.sh) required
`len(rows) == 1` for the task_id and silently `sys.exit(2)` otherwise. The blocked lane had
TWO rows (both `pid_role=lead_durable`, both pid 79117 — the INTERACTIVE lead session, not a
worker). With two rows the release could never succeed, independent of who owns the row, so
`lane_is_live` held forever and the counter grew on every dispatch.

## Changes

1. **Release works despite duplicate rows** (req 1) — `_release_registered_lane` python now
   processes rows per-row instead of failing whole. A row is removed iff
   (its `session_id`+`pid` match THIS attempt's registration — the R5 owner check, preserved)
   OR its pid is dead (stale duplicate). Live foreign rows still fail closed (rc 2).
   Python rc 4 = duplicate rows, none removable.
2. **Duplicate rows are visible** (req 2) — the python prints a `rows=N removed=M
   live_worker_kept=K` summary; the shell emits `active_lane_duplicate_rows ... found=N` into
   the decision journal whenever N>1, and the skip line for the duplicate case is
   `reason=duplicate_rows_unresolvable` (previously indistinguishable from "foreign row").
   Note: the summary travels via a temp file because bash (even 5.x) cannot parse a heredoc
   inside `"$( ... )"` — measured, see "bash 3.2/5.3 heredoc-in-substitution" below.
3. **Liveness is not just "PID alive"** (req 3) —
   - `leadv2-active-registry.sh`: new `_proc_kind(pid)` reads the LIVE argv via
     `ps -o args=`; a row's process kind is `worker` (`claude/codex ... -p/--print`),
     `interactive` (`claude` / `--dangerously-skip-permissions`), `other` or `dead`.
     Every registered row now stamps `proc_kind` alongside the existing (pid, pid_birth)
     pair, refreshed on register-refresh.
   - `_release_registered_lane` consumes the kind: a row is never released if
     `pid_role == "worker"` (existing) OR its live process argv classifies as `worker`
     (new, defence in depth against a mislabelled row — this is exactly the incident shape).

## Negative controls (one per changed requirement, all run)

Suite: `plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh` — extracts the real
`_release_registered_lane` from `leadv2-dispatch-code.sh` (no copy of production code) and
runs it in a harness with a stubbed journal. Mutations are inserted INSIDE the function body
of a temp copy of the production script. rc pairs use the journal-mirrored release code
(`_release_registered_lane` returns 0 by design; the journal line is its observable outcome).

Final green run:

```
[TEST] PASS: T1 baseline_rc=0 (release succeeds despite duplicate row)
[TEST] PASS: T1 both rows released
[TEST] PASS: T1 duplicate row count journaled (req 2)
[TEST] PASS: T2 foreign live row skipped rc=2
[TEST] PASS: T2 foreign row survives
[TEST] PASS: T4 live worker row survives release
[TEST] PASS: T4 surviving row is the worker row
[TEST] PASS: T4 journal names kept live worker
[TEST] PASS: T5 mislabelled live-worker row survives kind guard
[TEST] PASS: M1 mutated_rc=4 differs from baseline_rc=0 (release control bites)
[TEST] PASS: M1 red line present: decision active_lane_release_skipped task=prlr0001 id=task-prlr0001 where=unit_test reason=duplicate_rows_unresolvable rows=2 removed=0 live_worker_kept=0
[TEST] PASS: M2 mutated: duplicate journal line gone (baseline had it) — control bites
[TEST] PASS: M3 baseline_rc=2 (kept) vs mutated_rc=0 (released live worker) — control bites
[TEST] PASS: T6 registry stamps proc_kind on the registered row
[TEST] PASS: M4 baseline stamps proc_kind=True vs mutated=False — control bites

[TEST] PASS=15 FAIL=0
SUITE_RC=0
```

Red output that preceded the fix (mutation M1 against the OLD behaviour is not directly
constructible post-fix; the honest red sequence during development was):
- first run against the old release code: T1 `baseline_rc` was 0-but-no-write, exposed the
  filter bug `if s not in rows` after `rows.remove(...)` (rows was already empty → nothing
  filtered). Fixed with an identity-based `removed_ids` filter. M1 red line:
  `reason=duplicate_rows_unresolvable rows=2 removed=0` (the mutation re-creates the old
  fail-whole behaviour; baseline rc 0 vs mutated rc 4).
- M3 red run: `M3 unexpected rc pair base=2 mut=2` — the harness passed the harness pid
  instead of the fake worker pid, so the row was foreign even without the kind guard. Fixed
  by passing `FAKE_WORKER_PID`; final pair base=2 (kept) vs mutated=0 (released).

Control → requirement map:
- M1 (kill per-row removal predicate) → req 1: baseline_rc=0 vs mutated_rc=4.
- M2 (kill `active_lane_duplicate_rows` emit) → req 2: journal line present vs gone.
- M3 (kill process-kind guard) → req 3: mislabelled live-worker row kept (rc 2) vs released (rc 0).
- M4 (remove `proc_kind` stamp in register dict) → req 3: stamp present vs absent.

Acceptance #3 (no live worker released): T4 — a row with `pid_role=worker` and a LIVE
process (fake `claude -p` fixture, real `ps` classification) survives the release path, and
the journal line carries `live_worker_kept=1`; T5 proves the kind guard independently of the
pid_role label.

## Suite registration (acceptance #2)

Appended two rows to `EXTRA_SUITE_MAP` in `tests/run-all.sh` (append-only, applied via temp
file + `mv`; `bash -n` green). Runner plan dump on the REAL edit (no touch trick):

```
[SELECT] .../plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh
```

(`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`, grep for the suite.)

## Self-check (falsification set)

- `bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh` → SYNTAX_OK
- `bash -n plugins/leadv2/scripts/leadv2-active-registry.sh` → SH_OK
- `bash -n tests/run-all.sh` → RUN_ALL_SYNTAX_OK
- `bash -n plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh` → ok
- embedded registry python extracted (`sed -n '232,822p'`) → `python3 -m py_compile` → PY_OK
- adjacent regression suites, foreground:
  - `test-active-registry-failclosed` rc=0 (PASS=3 FAIL=0)
  - `test-active-registry-update-phase` rc=0 (PASS=7 FAIL=0)
  - `test-phase-precondition` rc=0 (pass=79 fail=0)
  - `test-lane-registry-outlives-dispatcher` rc=1 — PRE-EXISTING red: re-run with HEAD
    versions of both modified scripts → also red (4 passed/6 failed; with my change
    5/6 — one fewer failure). Not in tests/known-red-suites.txt; left untouched per
    lane boundaries (its remaining failure is `dispatch exited 4 (expected 0)` wiring,
    unrelated to release semantics).

## Limits

- Plugin-cache caveat (stated explicitly, per brief): the fix is verified by the suite on
  this worktree's copies only. The LIVE dispatcher runs from the plugin cache — a separate
  real file — so the running system is NOT fixed until the cache is refreshed/reinstalled
  from this repo (and hooks/script cache semantics per PLUGIN-CACHE-DEPLOY memory).
- macOS-only verification (`ps -o args=`, BSD flags); Linux CI may classify argv slightly
  differently for non-claude processes — the `worker` detection keys on argv content
  (`claude`/`codex` + `-p`/`--print`), not on ps dialect, but it is UNVERIFIED on Linux.

## Files changed

- `plugins/leadv2/scripts/leadv2-dispatch-code.sh` — per-row owner-verified release,
  duplicate-row journal line + `reason=duplicate_rows_unresolvable`, process-kind guard,
  release summary capture via temp file.
- `plugins/leadv2/scripts/leadv2-active-registry.sh` — `_proc_kind()`; `proc_kind` stamped
  on register and refreshed on register-refresh.
- `plugins/leadv2/scripts/tests/test-phase-refusal-lane-release.sh` — new suite (15 asserts,
  4 in-function mutation controls).
- `tests/run-all.sh` — two EXTRA_SUITE_MAP rows appended.
- `docs/handoff/PHASE-REFUSAL-LEAVES-A-LANE-REGISTERED-01/report.md` — this file.

No runtime-state paths touched (`docs/leadv2/`, `docs/LEAD_V2_STATE.md`,
`docs/handoff/dispatch-nw*` all untouched); `tests/known-red-suites.txt` untouched.
