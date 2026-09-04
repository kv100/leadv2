# dispatch-6b17ca52 — developer.full.md

## Scope

Implemented the mechanism-closed design HOOK-INJECT-DEDUP-01 fix round 1 as scoped in
the design doc pasted into the mission (§5, LANE_WRITES: `plugins/leadv2/hooks/leadv2-task-anchor.sh`,
`plugins/leadv2/scripts/tests/test-inject-dedup.sh`, `plugins/leadv2/docs/context-diet.md`).
No deviation from LANE_WRITES; the sibling renderer in persona-engine was read-only reference,
never edited.

## Prepass — design census check

Re-verified the design's three divergence notes (§0) against the live code before
implementing; all three held:
- §0.1: no separate python startup exists — confirmed the gate already runs inside the
  single heredoc interpreter opened at old line 59 / closed near old line 831.
- §0.2: `2>/dev/null` on the heredoc invocation did swallow all python stderr; removing it
  was required for finding 5 to have any effect. Verified `main()` is wrapped in
  `try/except Exception: pass` and all `subprocess.run` calls use `capture_output=True`,
  so no traceback/child-stderr leak is possible in normal operation.
- §0.3: confirmed by reading `scheduled-decisions-nearest.sh:135-148` (actually lines
  143-145 in the live file) — the renderer's suppression is `nearest_id == prev_id -> exit 0`,
  classification-blind. The design's own honest disclosure (the re-injected body may not
  itself name the overdue row even after this fix) was reproduced during test debugging
  (see "Notable deviation" below) and is preserved as documented residual, not silently
  fixed beyond scope.

No falsification of the design's census was found — implemented as designed.

## Changes

### `plugins/leadv2/hooks/leadv2-task-anchor.sh`

1. Removed `2>/dev/null` from the `python3 -` heredoc invocation (was on old line 59);
   added `import datetime` to the heredoc's top-level imports.
2. Added `_inject_warn(err)` — writes one bounded `[inject-dedup] fail-open: <Type>: <msg>`
   line to stderr, itself exception-swallowed.
3. Added `_nearest_decision_signature(root, leadv2_dir)` — parses
   `docs/leadv2/scheduled-decisions.md` directly, grammar mirrored from
   `scheduled-decisions-nearest.sh` (heading regex, three field-regex passes, date
   extraction, OVERDUE/DUE_TODAY/CONDITION_BOUND tiering, tier-then-position sort).
   Returns `""` (absent ledger), `"none"` (no actionable row), `"oversize"` (over
   `LEADV2_SD_SCAN_MAX_BYTES`, default 8 MiB), or `"<row_id>:<STATUS>"`. Never raises —
   wrapped in try/except calling `_inject_warn`.
4. `_inject_dedup_gate()` signature extended to `(kind, session_id, body, root=None,
   leadv2_dir=None)`; digest is now `sha256(body + "\n" + today + "\n" + sd_sig)`. The
   two broad `except Exception` fail-open blocks (GC sweep, outer gate handler) now call
   `_inject_warn(exc)` before returning `"full"`.
5. Call site (old line 625) updated to pass `root, leadv2_dir` (both already in scope in
   `main()`, used identically by `build_thread_anchor` two lines above).

### `plugins/leadv2/scripts/tests/test-inject-dedup.sh`

Added three cases plus one fixup:
- Fixed the G5 test's hand-written stale digest to use the new 3-part formula (cosmetic;
  it worked either way since the test only needs a stored digest that mismatches today's).
- **G5b**: writes a real `docs/leadv2/scheduled-decisions.md` fixture, one row, Due=today
  → confirms marker on unchanged 2nd fire, then flips Due to 3 days ago (same row id,
  nothing else changed) → confirms full re-inject. Isolated from G4 because the sandbox
  repo has no `.claude/hooks/scheduled-decisions-nearest.sh`, so `nearest_due_line()`
  returns `None` and the rendered body genuinely never varies with the Due date.
- **finding-3**: explicitly creates `/tmp/.leadv2-task-anchor-full-<sid>-covertask` before
  the PreCompact fire (the sandbox's task-mode path at old line 645 never creates this
  file on its own, since the fixture repo has no active task) — proves the existing
  PreCompact glob-clear actually covers this file, not vacuously.
- **finding-5**: reuses the existing G6 unwritable-state-dir fixture (real
  `PermissionError`, no test-only error-injection backdoor), captures stderr, asserts it
  contains `[inject-dedup] fail-open:`.

Result: `PASS=14 FAIL=0` (10 baseline + 4 new/split; see raw output below).

### `plugins/leadv2/docs/context-diet.md`

Corrected the digest description to the 3-part formula, added a paragraph explaining
`sd_signature`, why it's computed in-gate (renderer's own suppression is id-keyed), the
honest residual (full re-inject fires, but the body may not name the row — renderer
still stays silent on an unchanged id), and documented `LEADV2_SD_SCAN_MAX_BYTES` next to
`LEADV2_INJECT_DEDUP` and the new fail-open WARN line.

## Notable deviation from design text (bug found and fixed, not scope creep)

The design's own test-authoring note (§5.2a) suggested `date -u +%F` for "today" in the
new fixture. Implementing that literally caused a **real, reproducible test failure**:
`_nearest_decision_signature()` classifies against **local** `datetime.date.today()`
(matching the sibling renderer's own grammar — it also uses local time, not UTC), not
UTC. In this environment UTC and local dates currently differ by a day, so a `date -u`
"today" fixture and a "3 days ago" fixture both landed in the OVERDUE tier under local
time — same signature, test passed vacuously in reverse (failed to detect the flip it
was checking for). Fixed by deriving both fixture dates from
`python3 -c "import datetime; ..."` (local clock), matching the parser's actual semantics.
This is a test-authoring correction, not a change to the shipped mechanism or its
digest/classification logic.

## Self-check — falsification set (raw output)

```
$ bash -n plugins/leadv2/hooks/leadv2-task-anchor.sh && echo BASH_OK
BASH_OK
$ bash -n plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh && echo OK2
OK2
$ bash -n plugins/leadv2/scripts/tests/test-inject-dedup.sh && echo OK3
OK3
$ python3 -m py_compile /tmp/ta_final.py && echo PY_OK   # extracted embedded heredoc
PY_OK

$ bash plugins/leadv2/scripts/tests/test-inject-dedup.sh
[TEST] PASS: hook scripts parse
[TEST] PASS: G2->G3: second identical fire collapses to a one-line marker
[TEST] PASS: G4: changed content re-injects full block
[TEST] PASS: G5: a stored digest from a prior day forces full re-inject
[TEST] PASS: G0: LEADV2_INJECT_DEDUP=0 disables the gate on every fire
[TEST] PASS: G1: missing session id never collapses to the marker
[inject-dedup] fail-open: PermissionError: [Errno 13] Permission denied: '.../unwritable/nested'
[inject-dedup] fail-open: PermissionError: [Errno 13] Permission denied: '.../unwritable/nested'
[TEST] PASS: G6: unwritable state dir fails open, hook still exits 0
[TEST] PASS: R2 setup: marker present before compaction
[TEST] PASS: R2: PreCompact removes the stored digest for the compacting session
[TEST] PASS: R2: first prompt after /compact is a full re-inject, not a marker
[TEST] PASS: G5b setup: unchanged ledger (DUE TODAY) still collapses to marker
[TEST] PASS: G5b: DUE_TODAY -> OVERDUE classification flip forces full re-inject
[TEST] PASS: finding-3: PreCompact clears the /tmp task-anchor-full marker glob
[TEST] PASS: finding-5: fail-open path emits a [inject-dedup] fail-open: WARN on stderr
[TEST] Results: PASS=14 FAIL=0
exit=0
```

## Regression check on the wider suite (evidence, not scope)

`test-hook-token-mode-isolation.sh` shows one pre-existing failure ("parallel lead task
hook selected the wrong registry row") both with my changes and with the baseline HEAD
version of `leadv2-task-anchor.sh` swapped back in — confirmed by temporarily restoring
`git show HEAD:plugins/leadv2/hooks/leadv2-task-anchor.sh` into place, rerunning (same
FAIL=1 result), then restoring my working copy and re-verifying `bash -n` +
`test-inject-dedup.sh` still green. Not caused by this change; not touched, per mission
scope (LANE_WRITES does not include this suite).

## Deliberately out of scope (per design §6, confirmed still true)

1. Editing `scheduled-decisions-nearest.sh` in persona-engine — another repo, off-limits.
2. Making the renderer's own suppression classification-aware.
3. Surfacing the in-gate-computed OVERDUE line into the injected body itself (the
   residual described in design §4 — the re-inject now fires correctly, but the body's
   scheduled-decisions text still comes from the classification-blind renderer and may
   not mention the row that just went overdue). This is the honest gap the design flags
   as a lead-level call, not implemented here.
4. Clearing the renderer's own `${TMPDIR}/pe-nearest-due-<sid>` state on PreCompact
   (cross-repo).
5. `leadv2-single-lead-beat.sh`'s BROAD_STATUS gate, the task-mode anchor path's
   production code, `LEADV2_INJECT_DEDUP` semantics, the GC glob scope, the
   `tmp+os.replace` write pattern, ledger locking, and parser deduplication between the
   plugin and the renderer — all untouched, per design §6.

## Commit

`e12d43b` on branch `worktree-7bdb16ee`: "fix(inject-dedup): classify scheduled-decision
urgency in-gate (7bdb16ee)". 3 files changed (`leadv2-task-anchor.sh`,
`test-inject-dedup.sh`, `context-diet.md`), 226 insertions / 20 deletions. Only these
three lane-write files were staged; other modified/untracked paths in the worktree
(`docs/handoff/dispatch-nw*`, `docs/leadv2/.bus*`, `docs/leadv2/active.yaml*`,
`docs/leadv2/.compact-freeze.md`, etc.) are lead-owned state, not touched or committed by
this task.

DELIVERABLE_COMPLETE
