# KIMI-CHANNEL-REHAB-01 — critic review (sonnet, 2026-08-03)

Verdict: **BLOCK** (findings 1+2 critical, both silent, both uncovered by the new tests).

## CRITICAL 1 — no-work bail never reaches the spill logic it exists for
kimi-coder.sh `cmd_bg` (kimi-coder.sh:89-94) forks `__supervise` detached (setsid + disown) and
returns rc=0 immediately with run_id. The KIMI_CHANNEL_NO_WORK/exit=78 verdict is written later
by the detached process. leadv2-dispatch-code.sh:1608-1619 only inspects the synchronous rc of
the `bg` launch to decide spill — `bg` can never return 78 for a verdict not yet computed. The
spill branch is structurally unreachable. Tests (c)/(d) call kimi-coder.sh directly and assert
on progress.log/meta.yaml only — dispatch-code's reaction to async completion has zero coverage.

## CRITICAL 2 — admission guard fails closed for the target mission class
`_kimi_admissible` (leadv2-dispatch-code.sh:1189-1211) requires non-empty writes_csv, sourced
only from --writes or _prepass_writes(sig8). For --kind plugin/tooling/docs/diagnosis (lines
1143-1144, the narrow no-prepass path) no prepass runs → writes_csv empty → kimi skipped.
Live-verified: `--kind plugin --no-spawn "Fix one typo in one file."` → `kimi_skipped
reason=mission_too_broad chars=901 writes=0 prepass=0`. All 5 admission tests pass only because
every case manually threads --writes, masking this.

## MEDIUM 3 — journal reason hardcoded `mission_too_broad` for every rejection cause
(char overflow / empty writes / over-budget / prepass present) at leadv2-dispatch-code.sh:1225.
Most real skips will actually be writes=0 — misleading for triage.

## MEDIUM 4 — char budget measured AFTER ~870-char async-question boilerplate is appended
(injected ~line 2154-2166, admission check ~2306). 26-char mission counted as chars=901;
effective narrow budget ≈1630, not 2500. Confirm intent or measure pre-append.

## LOW 5 — no prior kimi/dispatch suite existed; new standalone test file created (scope note).

Verified clean: bash -n all touched + new test; mission_is_code_shaped/work_delta_present reuse
N2-DEADHAND-SUBSTANCE infra; exit-78 disambiguated via KIMI_CHANNEL_NO_WORK sentinel (sound in
isolation, moot given finding 1); test-kimi-admission-guard.sh 5/5 pass with pre-supplied
--writes.

Risk if shipped as-is: reproduces the original 19/19-empty problem in a harder-to-see shape
(kimi in ladder but silently never admitted; no-work never spills).

DELIVERABLE_COMPLETE
