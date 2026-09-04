# BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01 — report

Lane commit: `2346b9c5` (base `0296f9c0`, merge-base with main `e5f00529`).
Root cause per brief holds: `_emit_ready_line` stamped `at=` from `$BEAT_AT`
(beat wall clock), and the final artifact write was unguarded.

## Files changed (2346b9c5)

- `plugins/leadv2/scripts/leadv2-broad-status.sh` — `_file_age_s()` (epoch
  file only; missing/non-numeric → epoch 0 = maximally stale, fail-SAFE);
  `_emit_ready_line`: `at=` from `FOUNDER_STATUS_EPOCH_PATH` (fallback stat
  mtime, last resort `$BEAT_AT`), `stale=1` when age >= BEAT_S (default
  1800), ABSOLUTE `path=`; final write guarded like the collector/render
  failure paths — failed `mv` → `_emit_fail_line`, never a fresh READY;
  product HH:MM line pinned to the same `$BEAT_AT` as line 1 (one gathering,
  one timestamp). `dedupe_value` stays on `$BEAT_AT` (beat identity).
- `plugins/leadv2/hooks/leadv2-single-lead-beat.sh` — DELIVER owner-role
  gates: absolute epoch age < BEAT_S AND ready-line `at=` vs file line-1
  agreement within BEAT_S; either failure → `RELAY=refused` (publication
  REFUSED, not warned). `FOUNDER_STATUS_PATH` anchored absolute. Guest CTX
  carries the absolute path.
- `plugins/leadv2/scripts/tests/test-broad-status-stale-file.sh` — NEW
  suite, T1-T7 (see below). Self-select dir + `# run-all-triggers:
  leadv2-broad-status.sh leadv2-single-lead-beat.sh` header (addendum 1:
  EXTRA_SUITE_MAP no longer exists on main; run-all.sh untouched).
- `plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh` — cases 1-3
  now assert `at=` == epoch-derived ISO AND `at=` != forced BEAT_AT (old
  assertion compared a value to a copy of itself); artifact/epoch resolved
  via state resolver `--no-link`.
- `plugins/leadv2/scripts/tests/test-broad-status-duty.sh` — ready-line
  shape updated (absolute path, epoch-sourced `at=`); T9c now checks stamp
  TRUTH (epoch) not self-agreement; beat_env pins the epoch path.
- `plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh` —
  `LEADV2_SESSION_KIND=lead` pinned in `real_hook_fire`, T6, T19 (the
  fail-closed classifier from BEAT-LOOP-ORPHANS-01 r2 silences
  transcript-less payloads; `hook_fire` was already pinned, these three
  fire paths were the missed half).

## Acceptance (brief §Acceptance, live script, macOS)

Brief's literal (a) is self-destructing as written: a successful run
REWRITES founder-status.md and stamps a fresh epoch, so the 25h fixture no
longer exists at READY time (observed: the brief's own command sequence
prints FAIL because the composer legitimately refreshed everything).
Equivalent live check (a') pins the epoch file unwritable — the state where
a stale confirmed write actually survives a run:

    (a') READY: ... at=2026-09-03T18:01:52Z path=/tmp/broad-status-accept/docs/leadv2/founder-status.md rows=0 dispatched=unavailable stale=1   → PASS
    (b)  fresh run -> plain READY (no stale=1)                                                                  → PASS
    (c)  LINE_EPOCH=1788548541 FILE_EPOCH=1788548541  (at= == the file's own mtime)                             → PASS

Hermetic equivalents of all three live in the new suite (T1 stale=1 +
epoch-sourced at=; T2 plain READY + absolute path; T3 failed mv ->
BROAD_STATUS_FAILED, no READY).

## Falsification set (verbatim)

    $ bash plugins/leadv2/scripts/tests/test-broad-status-stale-file.sh
    [TEST] PASS: T1: 25h-old confirmed write -> READY stale=1, at= is the file's epoch stamp (not the beat clock)
    [TEST] PASS: T2: fresh beat -> plain READY, at= = this run's epoch stamp, path= absolute
    [TEST] PASS: T3: failed mv -> BROAD_STATUS_FAILED fires, no READY over the day-old file
    [TEST] PASS: T4: hook refuses to relay a 25h-old confirmed write
    [TEST] PASS: T5: hook refuses on ready-line vs file line-1 stamp mismatch (7200s apart)
    [TEST] PASS: T6: fresh agreeing stamps still get RELAY=full
    [TEST] PASS: T7: artifact line-1 stamp and product HH:MM both come from the pinned BEAT_AT
    ----------------------------------------
    test-broad-status-stale-file: 7 passed, 0 failed

    $ bash plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh
    test-beat-stamp-agreement: 6 passed, 0 failed

    $ bash plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh
    25 passed, 0 failed

    $ bash plugins/leadv2/scripts/tests/test-broad-status-duty.sh
    === 18 passed, 20 failed ===

`bash -n` clean on all six shell files (script, hook, four suites).

### duty's 20 reds are pre-existing on this machine (baseline proof)

Baseline run at merge-base `e5f00529` (original hook/script/suites,
`git archive` scratch): `=== 16 passed, 22 failed ===` — the lane's failure
set (T3a/T3b, T4a-T4f, T9a/T9b assertion rows, T7, T8b) is a strict SUBSET;
the baseline additionally fails T9c-healthy and T9c-degraded, which this
lane's fix turned green. T4/T3 (live supervise-loop adoption) and T7/T8b
(beat-cron logging, supervisor-role.md wording — the file lacks the wording
on main too) are environmental/pre-existing, not touched by this lane's
diff. Same failure set reproduced twice in the lane tree (concurrent and
solo runs) — deterministic.

## Mutation control (the negative control IS the deliverable)

Per lead addendum §3: mutation inside `_emit_ready_line`'s body so `at=`
returns to `$BEAT_AT`; the suite goes red on the T1 staleness assertion
specifically (stale=1 still present, but `at=` is the beat clock again —
the original defect shape). Artifact
`mutation-control/20260904T192509Z-59329.txt`:

    suite=plugins/leadv2/scripts/tests/test-broad-status-stale-file.sh
    file=plugins/leadv2/scripts/leadv2-broad-status.sh
    anchor=s/"\$(_now_iso)" "\$at_iso"/"$(_now_iso)" "$BEAT_AT"/
    baseline_rc=0
    mutated_rc=1
    red_line=[TEST] FAIL: T1: stale labeling wrong: ready=[2026-09-04T19:25:05Z [SUPERVISE-URGENT] BROAD_STATUS_READY at=2026-08-19T09:00:00Z path=... rows=0 dispatched=2 stale=1] expected_at=[2026-09-03T18:25:04Z] beat_at=[2026-08-19T09:00:00Z]
    diff_hash=f66e812d638aa501de4e463a6f7674daabe027f072bc1ed8850079e557055794
    lane_diff_hash=7fedf70cd32c6491f518a9c6daa3c4cc5410817dd57c06164c48d0d5a4d924d2

Addendum §3's second control (write guarded, `mv` fails ->
BROAD_STATUS_FAILED fires, READY does not) is suite case T3, green.

`tests/run-all.sh` was NOT run in this live checkout (addendum §4 hazard);
the new suite sits in a self-selecting conventional dir and carries the
run-all-triggers header for main's scanner.

## Notes for review

- Off-limits files untouched: `leadv2-dispatch-code.sh`, route arbiter,
  routing yaml, salvage branches, `leadv2-alarm-dedupe.sh`,
  `tests/known-red-suites.txt`.
- No runtime-state paths committed (docs/leadv2/, LEAD_V2_STATE.md,
  dispatch-nw* left as harness writes, uncommitted).
- The brief's negative-control section (mutate `_file_age_s` to force 0) is
  superseded by addendum §3 (mutate inside `_emit_ready_line`); the executed
  control is the addendum's.
