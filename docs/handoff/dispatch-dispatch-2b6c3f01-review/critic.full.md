# critic — PULSE-IS-A-PLUGIN-DUTY-01 diff review (/tmp/pulse.diff)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=2 medium=3 low=4

FINDING: severity=Critical file=plugins/leadv2/scripts/tests/test-broad-status-duty.sh line=59 dimension=correctness desc=PUMP_COUNTER is never exported, so the pump stub writes to an empty path and T3a always fails — the suite as shipped cannot pass
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-supervise-loop.sh line=845 dimension=correctness desc=the beat-branch `pump check` is the SECOND pump run of the same cycle (line 818 already ran it), so the stamped dispatched= is systematically 0 and understates real dispatches
FINDING: severity=High file=plugins/leadv2/scripts/tests/run-core-offline.sh line=102 dimension=correctness desc=test-broad-status-duty.sh is not registered in the core-offline runner, so the whole delivery invariant is unguarded in CI

Scope: only `/tmp/pulse.diff`. The two `docs/leadv2/tasks/*/journal.md` hunks are append-only log noise and were not reviewed.

---

## Critical

### C1 — the new suite cannot pass: `PUMP_COUNTER` is not exported to the pump stub
`plugins/leadv2/scripts/tests/test-broad-status-duty.sh:59` (stub body ~line 107, assertion at line 190–196)

`PUMP_COUNTER="$TMP/pump-counter"` is a plain shell variable. The pump stub's heredoc is
unquoted (`<<EOF`) but deliberately escapes the reference (`\$PUMP_COUNTER`), so the path is
resolved **at stub run time, from the stub's environment**. The stub is executed by
`leadv2-supervise-loop.sh` via `bash "$PUMP_SH" check`, in a process tree launched by
`loop_env` = `env LEADV2_… CRONTAB_BIN=… bash "$LOOP_SH"`. `PUMP_COUNTER` is in none of those
env assignments, so inside the stub it expands to the empty string.

Reproduced verbatim (stub copied byte-for-byte from the diff, invoked exactly as the loop
invokes it):

```
$ env FOO=bar bash -c 'bash "$1" check' _ /tmp/stubtest/pump.sh
/tmp/stubtest/pump.sh: line 5: : No such file or directory
check complete: examined=1 dispatched=2 live=0 remaining_capacity=5 below_floor=0
counter exists? NO
```

Consequence, line by line:
- `echo $((n + 1)) >"$PUMP_COUNTER"` → redirect to `""` → fails. No `set -e` in the stub, so
  execution continues and the `check complete:` line is still emitted on stderr.
- T3b (`dispatched=2` in the ready-line) therefore **passes for the wrong reason**.
- T3a's guard `[[ -f "$PUMP_COUNTER" && -f "$FOUNDER_STATUS" ]]` is false →
  `fail "T3a: pump counter or founder-status.md missing after one loop cycle"`.
- `FAIL > 0` → the suite exits 1. The one test that claims to prove C2's central
  "dispatch before report" ordering is the one that hard-fails.

**Required fix:** `export PUMP_COUNTER CRONTAB_STUB_STATE` before the stubs are written (or
interpolate the literal path at heredoc-write time by leaving `$PUMP_COUNTER` unescaped).
Then re-run the suite and paste real output — do not claim green without it.

---

## High

### H1 — the beat's `dispatched=` count is systematically wrong (the pump already ran this cycle)
`plugins/leadv2/scripts/leadv2-supervise-loop.sh:843–851`, against the pre-existing
`_run_pump_on_close` call at `:818` → `:430`.

Every loop iteration already ends with `_run_pump_on_close "$OUT"` (`:818`), whose tail is an
unconditional `bash "$PUMP_SH" check` (`:430`), gated by the same `LEADV2_BACKLOG_PUMP` flag
and documented as *"Refill regardless of whether anything closed THIS cycle."*

The new beat branch then runs `bash "$PUMP_SH" check` a **second** time, milliseconds later in
the same iteration, and stamps *that* run's count into the beat. The real pump only dispatches
when `remaining_capacity > 0`; the preceding call at `:430` has just consumed that capacity.
So in production the second call reports `dispatched=0` essentially always, and the founder's
status beat reads `dispatched=0` in exactly the cycles where lanes *were* dispatched seconds
earlier.

The header comment at `:835` ("its dispatched count is stamped into the beat, so 'a pulse
dispatches before it reports' is a code-enforced, after-the-fact auditable order") is therefore
false as written: the ordering is enforced, but the audited number is not the number of
dispatches in the beat window.

The test cannot catch this because the stub pump is stateless and returns
`dispatched=2` on every invocation regardless of capacity.

**Required fix:** do not re-run the pump in the beat branch. Have `_run_pump_on_close` capture
the count from its existing `:430` call into a loop-scoped accumulator (summed across cycles
since `LAST_BROAD_STATUS_EPOCH`), and export *that* as
`LEADV2_BROAD_STATUS_DISPATCHED`. That both removes the duplicate invocation and makes
`dispatched=` mean "dispatched during this beat window", which is what the founder will read
it as. If the double-run is kept deliberately, the field must be renamed to something honest
(e.g. `dispatched_at_beat=`) and the comment corrected.

### H2 — the new suite is not registered with the core-offline runner
`plugins/leadv2/scripts/tests/run-core-offline.sh` (explicit `run_check` list, lines 82–102)

`run-core-offline.sh` enumerates suites one `run_check` line at a time; there is no glob. The
diff adds `test-broad-status-duty.sh` and registers it nowhere, so nothing in the repo ever runs
it. The invariant this whole task exists to protect ("a beat wakes the lead") regresses silently
the first time someone touches `_emit_ready_line`.

This is the same class of gap already tracked in `docs/leadv2/open-threads.md` (suites present
on disk, absent from every runner).

**Required fix:** add
`run_check "broad-status delivery duty" bash "$TEST_DIR/test-broad-status-duty.sh"` to
`run-core-offline.sh`. Note the suite's own header admits ~60s per loop cycle and T4 waits up to
240s — if that is too slow for the core lane, register it in whichever slower lane exists rather
than leaving it unregistered.

---

## Medium

### M1 — T3a's ordering assertion is vacuous
`test-broad-status-duty.sh:188–196`

T3a compares `mtime(PUMP_COUNTER) < mtime(FOUNDER_STATUS)`. Because `_run_pump_on_close`
(`leadv2-supervise-loop.sh:818`) already runs the pump earlier in the same cycle, that
comparison would hold **even if the entire C2 beat-branch pump block were deleted**. The test
does not discriminate the change it claims to protect. (Today it does not even get that far —
see C1.)

**Required fix:** assert on the *count*, not on mtime ordering: make the stub record one line
per invocation with a monotonic marker, and assert the beat's `dispatched=` matches the
invocation that immediately precedes the `founder-status.md` write. Or, once H1 is fixed, assert
the accumulated window count.

### M2 — `CRONTAB_STUB_STATE` is not exported; the crontab stub records nothing
`test-broad-status-duty.sh:60`, stub at ~line 118. Same defect shape as C1 — shellcheck flags it
directly:

```
In plugins/leadv2/scripts/tests/test-broad-status-duty.sh line 60:
CRONTAB_STUB_STATE="$TMP/crontab-state"
^----------------^ SC2034 (warning): CRONTAB_STUB_STATE appears unused. Verify use (or export if used externally).
```

`crontab -` writes to `""` and `crontab -l` cats `""`, so the recorded-install fixture is dead.
The real crontab is genuinely never touched (`CRONTAB_BIN` points at the stub), so this is not a
safety issue — but the fixture claims a capability it does not have, and any future assertion on
installed cron lines will silently pass on empty input.

**Required fix:** `export CRONTAB_STUB_STATE` alongside the C1 fix.

### M3 — T2c does not test the pass-through path it names
`test-broad-status-duty.sh:178–180`

T2c disables the dedupe lib (`LEADV2_ALARM_DEDUPE_BIN=/nonexistent-lib`) **and** supplies a new
beat identity (`11:00:00Z`). A fresh identity fires with or without the lib, so the assertion
`ready_count == 3` proves nothing about R2 ("lib absent → pass-through emit").

**Required fix:** re-run the *already-delivered* identity (`10:30:00Z`) with the lib disabled and
assert the count increments — that is the only run that distinguishes pass-through from dedupe.

---

## Low

### L1 — `rows=` can be empty in the ready-line
`leadv2-broad-status.sh:299`. If the `python3 -c … ['rows']` extraction fails (malformed
`render.json`, python3 missing at that instant), `ROWS_N` is empty and the beat emits
`… rows= dispatched=…`. T1c's regex requires `rows=0`, so the failure surfaces as a shape
mismatch rather than a clear error. Default it: `ROWS_N="${ROWS_N:--}"`.

### L2 — `rel_path` can leak an absolute path
`leadv2-broad-status.sh:73`. `${FOUNDER_STATUS_PATH#"$PROJECT_ROOT"/}` is a no-op prefix strip
when `LEADV2_FOUNDER_STATUS_PATH` points outside `PROJECT_ROOT`, so `path=` becomes an absolute
filesystem path — while `supervisor-role.md`, `leadv2.md`, the anchor hook and
`leadv2-supervisor-mode-reinject.sh` all instruct the lead to paste
`docs/leadv2/founder-status.md` literally. Either clamp to the relative form or drop the
override.

### L3 — same-beat double wake on a late composer failure
`leadv2-broad-status.sh:76` vs `leadv2-supervise-loop.sh:857–860`. The composer's success-path
`_emit_ready_line` is the last statement in the script, so its exit status is the script's exit
status. If the append to `$LOG_FILE` fails (full disk, permissions) the ready-line may already be
partially written *and* the loop then runs `_emit_broad_status_degraded "composer_rc_nonzero"`,
which never dedupes (its value carries `$(date +%s)`). Result: two wakes for one beat — the exact
cost the R1 invariant comment says must never happen. Narrow, but the invariant is stated
absolutely; either soften the comment or have the loop's degraded emit check the composer's own
transition first.

### L4 — leaked background shell + unused variable in T4
`test-broad-status-duty.sh:210`. `T4_LOOP_SHELL=$!` is assigned and never used (SC2034), and the
`timeout 240 loop_env … &` shell is never `wait`ed or killed — only `$OLD_PID`/`$NEW_PID` are.
The `timeout` wrapper can outlive the suite. Kill `$T4_LOOP_SHELL` in `cleanup()`.

---

## Notes on things that are correct (no action)

Checked and found sound, listed only because they were the likely failure modes:

- `leadv2_alarm_transition` return convention is `exit 0 = FIRE / exit 1 = SUPPRESS`
  (`lib/leadv2-alarm-dedupe.sh` header). The `! … && return 0` guard in both new emitters
  matches it.
- `PROJECT_ROOT` (`:17`), `LOG_FILE` (`:25`) and `FOUNDER_STATUS_PATH` (`:28`) are all defined
  before `_emit_ready_line` is *called*, so `set -u` is not tripped.
- `table_rows` (`:70`) is in scope at the `json.dump` on `:287` — same heredoc, already used at
  `:223`.
- The backlog pump's `check complete:` summary goes to **stderr** (`leadv2-backlog-pump.sh:99`),
  and the beat branch captures `2>&1` — the parse target is reachable.
- `leadv2-broad-status.sh` has no caller other than the beat branch, so the
  `LEADV2_SUPERVISE_BROAD_STATUS_S=0` "cannot half-work" rollback claim holds.
- `_install_beat_cron`'s new skip-log uses `_now_iso` (`:104`) and `$LOG_FILE`, both defined
  before the call site.

---

## Raw tool evidence

`mypy`/`tsc` are not applicable — this diff is bash, markdown and an embedded python heredoc.
Hard evidence run instead:

```
$ bash -n  (patched copies)
== plugins/leadv2/scripts/leadv2-broad-status.sh
  syntax ok
== plugins/leadv2/scripts/leadv2-supervise-loop.sh
  syntax ok
== plugins/leadv2/scripts/tests/test-broad-status-duty.sh
  syntax ok

$ shellcheck -S warning -e SC1091 leadv2-broad-status.sh tests/test-broad-status-duty.sh

In plugins/leadv2/scripts/tests/test-broad-status-duty.sh line 60:
CRONTAB_STUB_STATE="$TMP/crontab-state"
^----------------^ SC2034 (warning): CRONTAB_STUB_STATE appears unused. Verify use (or export if used externally).


In plugins/leadv2/scripts/tests/test-broad-status-duty.sh line 210:
T4_LOOP_SHELL=$!
^-----------^ SC2034 (warning): T4_LOOP_SHELL appears unused. Verify use (or export if used externally).

For more information:
  https://www.shellcheck.net/wiki/SC2034 -- CRONTAB_STUB_STATE appears unused...
```

(`leadv2-broad-status.sh` is clean at `-S warning`.)

C1 reproduction, stub copied byte-for-byte from the diff:

```
$ env FOO=bar bash -c 'bash "$1" check' _ /tmp/stubtest/pump.sh
/tmp/stubtest/pump.sh: line 5: : No such file or directory
check complete: examined=1 dispatched=2 live=0 remaining_capacity=5 below_floor=0
counter exists? NO
```

The suite itself was **not** executed end-to-end (T4 alone budgets 240s of real sleeping against
a live loop + watchdog, and C1 guarantees a non-zero exit before that matters). Stating that
explicitly rather than claiming a green run.

**Verdict: BLOCK.**

DELIVERABLE_COMPLETE
