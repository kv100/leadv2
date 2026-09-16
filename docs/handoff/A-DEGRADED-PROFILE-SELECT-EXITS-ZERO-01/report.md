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
