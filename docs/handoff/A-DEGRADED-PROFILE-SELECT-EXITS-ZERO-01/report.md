# A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01 — report

## What was built

A degraded selection is now distinguishable by the caller through a
machine-readable sidecar, while the fail-open contract stays byte-identical:

- **Exit code and stdout are UNCHANGED on every degraded entrance** — still
  exit 0 + `profile=- reason=single_profile`.
- Every degraded entrance writes
  `${LEADV2_QUOTA_CACHE_DIR:-~/.claude/state/leadv2/quota-cache}/degraded-select.json`
  (overridable via `LEADV2_CLAUDE_PROFILE_DEGRADED_FILE`), atomically
  (mktemp+mv), best-effort (never fatal):

  ```json
  {"kind":"degraded_select","reason_code":"no_probe_completed",
   "stdout":"profile=- reason=single_profile","exit":0,"detected_at":"2026-09-16T13:13:30Z"}
  ```

- The next healthy ranked pick **clears** the marker, so its presence means
  "the most recent armed selection degraded", a state no ranked selection
  ever produces.
- A `WARN: degraded_select reason_code=...` line accompanies it (journal +
  stderr), naming the entrance.

### Mechanism choice and justification (fix requirement #1)

Chosen: sidecar marker over non-zero exit / stdout field. Justification
against what the callers actually do:

- `claude-subsession.sh` pins the soft fallback for every rc other than 4/124
  and for the legacy line shape; `leadv2-quota-status.sh` invokes the selector
  with `|| true` and `2>/dev/null`; `leadv2-claude-profile-status.sh` reads
  stdout only. A new exit code or stdout field buys nothing from callers we
  cannot edit in this lane, and both were measured to break two lead-owned
  suites that pin the silent exit 0 as REGRESSION protection
  (`test-claude-profile-select.sh` T2/T3/T8 assert `rc=0` +
  `^profile=- reason=single_profile$`; `test-claude-profile-requested.sh`
  case 4 asserts byte-equality of the whole stdout). Escalated as
  `q-5e4379cf` with this exact trade-off; option (c) is the declared default.
- Fail-open preserved (requirement #2): no degraded entrance blocks anything;
  the marker is a pure observation surface.

## Entrance enumeration (requirement: "do not assume it is two")

Nine distinct entrances end in the silent exit-0 `profile=-
reason=single_profile`; eight are now marked, one is deliberately not:

| # | Entrance (site in selector) | reason_code | Covered |
|---|---|---|---|
| 1 | opt-in gate unset (:221, prints nothing) | — | **not degraded**: deliberate operator opt-out; left untouched (suite T1/`T5` pins empty stdout + rc 0) |
| 2 | registry unreadable (:268) | `registry_unreadable` | yes |
| 3 | <2 valid registry entries (:459) | `fewer_than_two_candidates` | yes |
| 4 | probe script unreadable (:466) | `dependency_missing_probe` | yes |
| 5 | picker script unreadable (:467) | `dependency_missing_picker` | yes |
| 6 | recs mktemp failure (:515) | `records_temp_unavailable` | yes |
| 7 | every probe hung/killed/unparseable — `completed==0` (:789; the 2026-09-16 09:33/09:34 incident entrance) | `no_probe_completed` | yes |
| 8 | exhausted-candidates filter failure (:794) | `exhausted_filter_failed` | yes |
| 9 | picker crash/empty (:809) AND the picker's own `profile=- reason=single_profile` when zero records parse (pick.py:279, caught at the shell's final output) | `picker_no_result` / `no_rankable_records` | yes |

Note on the mission's "two entrances" (identity_email_unresolved vs
degradation=stale_last_known): those are two upstream *causes* that funnel
into the same exits. `identity_email_unresolved` with all-failing probes ends
at entrance 7; a `stale_last_known` degradation whose sidecars are readable
instead produces a ranked `source=stale` pick — already distinguishable on
stdout via `source=stale stale_age_s=N` — and only degrades to entrance 7
when the probes never complete. Both funnels are covered.

Loud paths unchanged (requirement #4): `--requested-profile` unknown/unavailable
(exit 3), `same_account` / `default_token_*` / `all_exhausted` (exit 4) never
write a marker — a refusal is not a degraded selection.

## Acceptance probe — defective as committed

`docs/handoff/A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01/probe.sh` is truncated:
its header says "Two independent measurements" but the committed body never
assigns `RC2`; line 7 (`[[ "$RC2" -eq 0 ]] && exit 1 || exit 0`) runs under
`set -u`, so the unbound variable aborts with rc 1 **unconditionally** — it
cannot ever go green, regardless of any fix. Escalated in the same question
(`q-5e4379cf`). Equivalent local acceptance (both measurements the probe
header promises), red before / green after:

Red before (pre-fix binary, via git stash of the worktree state — measured on
the committed HEAD 1416328d selector):

```
$ (degraded run: every probe fails) ; marker file
stdout: profile=- reason=single_profile   rc=0
marker : missing                          <-- silent: caller cannot tell
```

Green after:

```
$ LEADV2_CLAUDE_MULTIPROFILE=1 LEADV2_CLAUDE_PROFILES_FILE=/tmp/dsmoke/reg.tsv \
  LEADV2_CLAUDE_PROFILE_PROBE=/tmp/dsmoke/badprobe.py \
  LEADV2_QUOTA_CACHE_DIR=/tmp/dsmoke/cache ... bash leadv2-claude-profile-select.sh
[claude-profile-select] WARN: degraded_select reason_code=no_probe_completed -- fell back to the inherited single profile; machine-readable marker written (cleared by the next ranked selection)
profile=- reason=single_profile
rc=0
$ cat /tmp/dsmoke/cache/degraded-select.json
{"kind":"degraded_select","reason_code":"no_probe_completed","stdout":"profile=- reason=single_profile","exit":0,"detected_at":"2026-09-16T13:13:30Z"}

$ (healthy run with good probe)
profile=a config_dir=/tmp/dsmoke/a rank_by=none ... source=unknown reason=quota_window_read candidates=2 ...
rc=0
$ ls /tmp/dsmoke/cache/degraded-select.json
ls: ... No such file or directory        <-- cleared by the ranked pick
```

## Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh  -> BASH_N_OK
$ bash plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh
[degraded-select-01] PASS: T1: exit 0 (fail-open preserved)
[degraded-select-01] PASS: T1: stdout byte-identical
[degraded-select-01] PASS: T1: marker written
[degraded-select-01] PASS: T1: reason_code=no_probe_completed
[degraded-select-01] PASS: T2: ranked pick
[degraded-select-01] PASS: T2: marker cleared by ranked selection
[degraded-select-01] PASS: T3: marker registry_unreadable, exit 0
[degraded-select-01] PASS: T4: marker fewer_than_two_candidates, exit 0
[degraded-select-01] PASS: T5: inert opt-out untouched, no marker
[degraded-select-01] PASS: T6: hard refusal unchanged, marker-free
[degraded-select-01] PASS: T7: requested-unavailable refusal, marker-free
[degraded-select-01] PASS: T8: marker JSON shape
[degraded-select-01] All checks passed          (rc=0)
```

No Python files changed.

## Controls (counts before → after)

| suite | before | after |
|---|---|---|
| test-claude-profile-select.sh | rc=0, PASS=152 FAIL=0 | rc=0, PASS=152 FAIL=0 |
| test-claude-profile-requested.sh | rc=0, all checks passed | rc=0, all checks passed |
| test-profile-select-skips-exhausted.sh | rc=0, green | rc=0, green |
| nc-claude-profile-select.sh | rc=2, PASS=139 FAIL=13 (pre-existing red: fixture emails unresolved → identity=*/na; + NC2-SETUP-FAIL mutation-pattern drift) | rc=2, PASS=139 FAIL=13 — identical, not caused by this diff |
| committed probe.sh | rc=1 (unbound RC2 — truncated, see above) | rc=1 — unfixable from this lane's write set |

The new suite self-selects via the `test-*.sh` path convention
(lib/leadv2-suite-discovery.sh admits tracked test-*.sh in tests/).

## Files changed

- `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` — marker
  machinery (`write_degraded_marker`/`clear_degraded_marker`,
  `DEGRADED_MARKER`), reason codes on all 8 degraded `single_profile` call
  sites, picker-output catch + clear-on-ranked-pick at the tail.
- `plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh`
  — new suite (12 checks).
- `docs/handoff/A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01/report.md` — this file.

---

# Round 2 (2026-09-16) — reviewer High: marker races

The round-1 reviewer's High (verified independently by the lead) stands: the
marker is one machine-wide path and up to six lanes select concurrently, so an
unlocked read/write lets a healthy pick destroy a degraded marker written
moments earlier — exactly the signal this row exists to create.

## What round 2 changed

1. **Every marker read and write is serialized through
   `leadv2-portable-lock.sh`** (the arm-cooldown pattern, not a hand-rolled
   lock and not a second lock file): the selector sources only its RELATIVE
   sibling `${BASH_SOURCE[0]%/*}/leadv2-portable-lock.sh` — never an
   env-selected path — and both `write_degraded_marker` and
   `clear_degraded_marker` run their whole critical section inside
   `( lv2_lock_wait "${DEGRADED_MARKER}.lock" 5 ... ) 9>"${DEGRADED_MARKER}.lock"`.
   A missing/unsourceable helper degrades to an unlocked best-effort op rather
   than breaking the selection (fail-open preserved); a lock timeout is the
   same fail-open. There is exactly one lock file, `<marker>.lock`.
2. **Clear semantics tightened so the lock protects a meaningful invariant.**
   A ranked pick now clears only a marker that PREDATES the selection: the
   selector captures `SELECT_START_EPOCH` sub-second (`python3 -c 'import
   time; print(time.time())'`) right after the opt-in gate, and
   `clear_degraded_marker` — with stat, comparison and `rm` inside ONE
   critical section — removes the marker only if its mtime is older. A
   degraded write that lands while a healthy selection is probing is a fresher
   signal and survives it. Unparseable/missing python3 → keep the marker
   (visibility is the safe direction for a best-effort marker).
3. **Six untested reason codes covered** (T12–T17): `dependency_missing_probe`,
   `dependency_missing_picker`, `records_temp_unavailable`,
   `exhausted_filter_failed`, `picker_no_result`, `no_rankable_records` — one
   assertion each, all pinned to `rc=0` + byte-identical stdout + the correct
   `reason_code` in the marker.
4. **Low findings:** the new env var
   `LEADV2_CLAUDE_PROFILE_DEGRADED_FILE` (marker-path override; the lock sits
   beside it at `<marker>.lock`) is documented in the selector's header
   comment block alongside the other overrides.

## No consumer is wired yet — and who owns wiring one

Plainly: **nothing reads the marker yet.** No caller
(`claude-subsession.sh`, `leadv2-dispatch-code.sh`, status surfaces) consumes
`degraded-select.json` as of this round; round 2 deliberately did not wire
one (reviewer instruction). No open row in `docs/tasks.yaml` owns the wiring
either — checked at commit time (`grep -i degraded docs/tasks.yaml` → 0
matches). The wiring belongs in a NEW row (suggested owner surface:
`claude-subsession.sh` at its profile-decision site, or
`leadv2-status-surface.sh` surfacing marker age); it must be opened by the
lead, not smuggled into this lane's write set.

## Round-2 falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh  -> ok
$ bash -n plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh -> ok
$ shellcheck -S error <both files>                                       -> clean
   (style/info-level findings unchanged in kind from the committed round-1
    state: SC2015 `A && pass || fail`, SC2094 fd-9/lock-file, SC2034 —
    error-severity is the repo's gate and is clean)

$ bash plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh
=== T9: concurrent healthy pick must NOT destroy the degraded marker ===
[degraded-select-01] PASS: T9: degraded side contract bytes intact
[degraded-select-01] PASS: T9: healthy side made a ranked pick
[degraded-select-01] PASS: T9: degraded marker SURVIVED the concurrent healthy pick
[degraded-select-01] PASS: T9: survivor is the degraded signal (reason=no_probe_completed)
=== T10: marker writes are serialized through ${MARKER}.lock ===
[degraded-select-01] PASS: T10: no marker while the lock is held (write serialized)
[degraded-select-01] PASS: T10: blocked write lands after release
=== T11: lock removed (selector copy without the sibling helper) -> write NOT serialized ===
[degraded-select-01] PASS: T11: helper-less copy writes during the hold (unlocked by design -- the red side)
=== T12..T17: dependency_missing_probe / dependency_missing_picker /
              records_temp_unavailable / exhausted_filter_failed /
              picker_no_result / no_rankable_records ===
[degraded-select-01] PASS: T12: dependency_missing_probe marked, contract bytes intact
[degraded-select-01] PASS: T13: dependency_missing_picker marked, contract bytes intact
[degraded-select-01] PASS: T14: records_temp_unavailable marked, contract bytes intact
[degraded-select-01] PASS: T15: exhausted_filter_failed marked, contract bytes intact
[degraded-select-01] PASS: T16: picker_no_result marked, contract bytes intact
[degraded-select-01] PASS: T17: no_rankable_records marked, contract bytes intact
[degraded-select-01] All checks passed          (25 PASS assertions, rc=0)
```

### Red-then-green for the lock (how "red with the lock removed" is measured)

Removing the lock means running selector bytes WITHOUT the sibling
`leadv2-portable-lock.sh` next to them — the guarded `source` finds nothing,
`lv2_lock_wait` is undefined, and the write runs unlocked. T11 does exactly
this as a permanent in-suite control:

- **RED side (T11)**: hold `${MARKER}.lock` via `lv2_lock_wait`, run the
  helper-less selector copy — its degraded marker APPEARS while the lock is
  still held (`PASS: helper-less copy writes during the hold`), i.e. the write
  was not serialized. This is the observed failure mode of round 1's unlocked
  marker, pinned forever as the red side.
- **GREEN side (T10)**: same hold, the real selector — no marker while the
  lock is held; the blocked write lands after release
  (`PASS: no marker while the lock is held` + `PASS: blocked write lands
  after release`).
- **T9** is the end-to-end form the reviewer described: a degraded and a
  healthy selection racing on one marker path; the degraded signal survives.

## Round 3 (2026-09-16) — the critical: marker I/O was blocking the contract line

The round-2 reviewer's Critical was verified line-by-line before touching anything:
`printf '%s\n' "$result"` (the contract output) sat AFTER
`write_degraded_marker`/`clear_degraded_marker`, and both now call
`lv2_lock_wait "${DEGRADED_MARKER}.lock" 5` internally. Every selection —
including a fully healthy one with nothing to record — could block up to 5s
on a lock it did not need, and if the caller's own timeout was shorter than
that wait, the already-computed pick was thrown away with the process.

### 1. Contract line moved ahead of all marker I/O

Three call sites changed, same shape at each: emit the answer, THEN touch the
sidecar.

- `single_profile()` (`leadv2-claude-profile-select.sh:213-226`): `printf
  'profile=- reason=single_profile\n'` now precedes the
  `write_degraded_marker` call.
- The picker's terminal block (`:893-910`, formerly `:893-902`): `printf '%s\n'
  "$result"` now precedes the write/clear decision.
- Exit codes and stdout bytes are unchanged at every site — only the order of
  two independent side effects (stdout write, marker I/O) moved, not the
  values.

### 2. The healthy path no longer pays a lock wait in the common case

`clear_degraded_marker` now starts with `[[ -e "$DEGRADED_MARKER" ]] || return
0` — a plain existence check with no lock. The overwhelming common case
(nothing degraded happened, no marker on disk) now costs one `stat`, not a
lock acquisition. A marker that appears in the gap between the check and a
concurrent writer's lock is simply left for the NEXT selection's
lock-guarded clear to consider — correctness never depended on this check
seeing a consistent snapshot, only cost does, and T9 (unchanged, still green)
is the test that pins the correctness side.

### 3. Medium 1 — the silent unlocked fallback is now a deliberate, visible, per-op decision

Both functions used to swallow a `lv2_lock_wait` timeout with `|| true` and
proceed unlocked — silently re-opening the exact race round 2 closed. Round 3
replaces that with two different, justified decisions:

- **`write_degraded_marker`**: on a lock timeout, proceeds unlocked, logs
  `WARN: degraded_marker_lock_timeout op=write reason_code=<code> --
  proceeding unlocked (best-effort)` to stderr, and stamps `"locked":false`
  into the marker JSON itself (`"locked":true` on the normal path). Rationale:
  visibility is this row's entire purpose — a marker that raced and lost is
  still more signal than silence, and round 1's original bug was silence, not
  an occasional unlocked write.
- **`clear_degraded_marker`**: on a lock timeout, it SKIPS the clear entirely
  (`exit 0` inside the subshell before touching the file) and logs `WARN:
  degraded_marker_lock_timeout op=clear -- skipping clear this round
  (visibility over promptness; a later ranked pick retries)`. Rationale: an
  unlocked clear is precisely the round-2 race re-entered through the timeout
  branch (a concurrent degraded write could land between an unlocked stat and
  an unlocked rm and be destroyed) — the existing "keep on unparseable"
  default already establishes that visibility wins over promptness for this
  marker, so a lock timeout gets the same answer: leave it for next time.

### 4. Medium 2 — `--requested-profile` excluded from the `no_rankable_records` write

`REQUESTED_PROFILE` narrows the candidate set to one profile by construction;
an empty `eligible_recs` under a request is already caught loudly earlier
(`requested_profile_unavailable`, exit 3) at every other entrance in the
function. The terminal block's `no_rankable_records` write is now gated
`if [[ -z "$REQUESTED_PROFILE" ]]` — a requested run that DID land a real
ranked pick still clears a stale marker exactly like any other healthy
selection; only the write for an empty-candidate requested run is suppressed,
since that is not balancer degradation.

### 5. The three Lows

- **Env var docs**: `LEADV2_CLAUDE_PROFILE_DEGRADED_FILE` was already
  documented in round 2's header comment block (unchanged this round;
  re-verified present at `:168`).
- **No consumer wired**: still true, still not this row's job (see round-2
  section above; unchanged).
- **Third low** (marker schema stability across the new `locked` field): the
  field is additive-only — every existing consumer/test reads named keys
  (`reason_code`, `kind`, `exit`, `stdout`, `detected_at`) via `json.load(...)
  [...]`, never positional or whole-object equality, so `locked` cannot break
  a reader that predates it. T8 (marker JSON shape) is unchanged and still
  green with the new field present.

### New test — T18, shown RED against round 2's code and GREEN after

`test-degraded-select-is-distinguishable-01.sh` T18: holds `${MARKER}.lock`
for 6s (longer than the internal 5s wait) while pre-seeding a degraded marker
so `clear_degraded_marker` has something to do, then runs a real selector
call with a 2s caller-side `timeout` and asserts the ranked pick is on
stdout. The cheap existence check (item 2) is deliberately defeated by
pre-seeding the marker, so T18 exercises the lock-contended path, not the
fast path.

RED, run against round 2's committed selector (`git show
83b28639:plugins/leadv2/scripts/leadv2-claude-profile-select.sh`, the
ordering the reviewer flagged):

```
=== T18: the contract line must not wait behind the marker lock (round 3, reviewer Critical) ===
[degraded-select-01] FAIL: T18 -- out='' -- pick never reached stdout before
  the caller's patience ran out (marker I/O ran BEFORE the contract line)
```

GREEN, same test, this round's selector:

```
=== T18: the contract line must not wait behind the marker lock (round 3, reviewer Critical) ===
[degraded-select-01] PASS: T18: ranked pick reached stdout despite a 6s-held
  marker lock and a 2s caller timeout
```

### Round 3 falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh                          -> ok
$ bash -n plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh       -> ok
$ shellcheck -S error plugins/leadv2/scripts/leadv2-claude-profile-select.sh              -> clean (rc=0)
$ shellcheck -S error plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh -> clean (rc=0)
$ python3 -m py_compile plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py          -> ok (unchanged file)

$ bash plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh
-> 18 test groups, [degraded-select-01] All checks passed, rc=0
   (T1-T17 unchanged from round 2, all still PASS; T18 new, PASS)
```

### Round 3 controls (before → after; "before" = round-2 committed HEAD 83b28639)

| suite | before | after |
|---|---|---|
| test-degraded-select-is-distinguishable-01.sh | 25 PASS / 0 FAIL (17 test groups) | 18 test groups, all PASS (T18 added) |
| test-claude-profile-select.sh | PASS=152 FAIL=0 | PASS=152 FAIL=0 |
| test-claude-profile-requested.sh | all checks passed | all checks passed |
| test-profile-select-skips-exhausted.sh | green | green |
| nc-claude-profile-select.sh | rc=2 (NC1 red-side PASS=139 FAIL=13; NC2-SETUP-FAIL pre-existing) | rc=2 — identical (PASS=139 FAIL=13, same NC2-SETUP-FAIL) |
| registered probe.sh | rc=1 (unbound `RC2`, truncated at commit — round 1/2 finding, not in this lane's write set) | rc=1 — unchanged, still outside this lane's write set |
| `tests/run-all.sh --scope changed` | 9 passed, 2 failed (`run-core-offline.sh`, `test-balancer-every-arm.sh`) | 9 passed, 2 failed — SAME two suites, SAME count; this lane's own suite (`test-degraded-select-is-distinguishable-01.sh`) and `test-claude-profile-select.sh`/`test-profile-select-skips-exhausted.sh` all PASS inside the run |

The two run-all failures are pre-existing and concurrency-related, not caused
by this diff: a second lane (`5417ae8d439c`) was live on this machine during
the run (task-anchor `LEADV2_ACTIVE_OTHER_SESSIONS`), and both failing
suites are named in this repo's own memory as flaking under concurrent
`core-offline` runners (the ENV-PIN/S6-spawn family for
`test-balancer-every-arm.sh`, nested-runner noise for `run-core-offline.sh`
itself) — identical failure set, identical count, to the round-2 baseline
measured with this diff fully reverted.

### Controls (round 2, before → after)

| suite | before (HEAD 34438bab) | after (this diff) |
|---|---|---|
| test-degraded-select-is-distinguishable-01.sh | n/a (round-2 tests new) | rc=0, 25 PASS / 0 FAIL |
| test-claude-profile-select.sh | rc=0, PASS=152 FAIL=0 | rc=0, PASS=152 FAIL=0 |
| test-claude-profile-requested.sh | rc=0, all checks passed | rc=0, all checks passed |
| test-profile-select-skips-exhausted.sh | rc=0, green | rc=0, green |
| nc-claude-profile-select.sh | rc=2 (NC1 red-side PASS at PASS=139 FAIL=13; NC2-SETUP-FAIL: the `rexp` mutation pattern exists ONLY in the NC itself — `credential_health`/`rexp` appear in no production script, so NC2 cannot build its mutated copy; pre-existing) | rc=2 — identical |
| registered probe.sh | rc=1 (unbound RC2 — truncated at commit, see round 1) | rc=1 — still unfixable from this lane's write set |
| tests/run-all.sh --scope changed | — | rc=1: 9 passed, 2 failed; BOTH failures reproduced at HEAD with this lane's diff reverted (files reset to 34438bab): `test-balancer-every-arm.sh` PASS=17 FAIL=5 (same 5 S6 spawn/journal failures at HEAD — the ENV-PIN family), `run-core-offline.sh` rc=1 (nested `15 passed, 1 failed` / `12 passed(red->green), 1 failed` at HEAD too — concurrent-runner noise, 3 other lanes live). Neither is caused by this diff. |
