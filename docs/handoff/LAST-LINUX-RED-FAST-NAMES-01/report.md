# LAST-LINUX-RED-FAST-NAMES-01 — report

`tests/test-status-surface-fast-names.sh` is now green on Linux (ubuntu:24.04
container) and still green on macOS. Nothing was added to
`tests/known-red-suites.txt`; no assertion was weakened.

## Root cause — TWELVE-LINUX-ONLY-SUITES-01 group A, eighth instance

`plugins/leadv2/scripts/leadv2-status-surface.5s.sh` used the BSD-first
mtime idiom at two sites (lock-age staleness check inside `_kick_refresh`,
and `PAYLOAD_AGE` in the cached-render branch):

    $(stat -f %m "$PAYLOAD" 2>/dev/null || echo 0)

On GNU coreutils, `stat -f` means "report on the filesystem" and exits 0
printing a multi-line dump whose first word is `File:` — so the `||`
fallback never fires and the captured value is that dump. The subsequent
`$(( ... ))` then aborts on `File:` as an identifier, the assignment never
happens, and under the widget's `set -uo pipefail` every later
`[ "$PAYLOAD_AGE" ... ]` dies with `File: unbound variable`. T2 (cold
cache) passed on Linux only because it early-exits before the
`PAYLOAD_AGE` site; T3/T4/T5 all traverse it — exactly the three CI
failures.

Changed (`plugins/leadv2/scripts/leadv2-status-surface.5s.sh`):
- new portable helper `_stat_mtime()` (OS switch:
  `uname -s == Darwin ? stat -f %m : stat -c %Y`, missing file → 0),
  mirroring the already-fixed `_mtime()` in `leadv2-status-surface.sh`;
- both call sites now use `_stat_mtime`.

## Negative control (mutation → red, revert → green, ubuntu:24.04 container)

Restoring the original `stat -f %m ... || echo 0` form at both sites:

    test-status-surface-fast-names: 9 passed, 3 failed   (rc=1)
      FAIL - warm cache (title='…5s.sh: line 372: File: unbound variable')
      FAIL - stale cache (title='…5s.sh: line 372: File: unbound variable')
      FAIL - rename hygiene (bashpath='' …)

— byte-identical to the CI failure signature (`bashpath=''`, the same three
cases). Revert → `12 passed, 0 failed`, rc=0.

## Verification

Linux (ubuntu:24.04 container, python3+git installed):

    test-status-surface-fast-names: 12 passed, 0 failed
    LINUX-RC=0

macOS (this machine, same commit):

    test-status-surface-fast-names: 12 passed, 0 failed
    MACOS-RC=0

`bash -n` clean on the changed file; no Python files changed. The
authoritative proof is the CI run on the merge of this lane.

## Exposure check (per brief)

`grep -ln 'stat -f %m' tests/*.sh` → no hits: no other `tests/`-level suite
carries the BSD-first stat idiom, so no second untested-on-Linux suite by
this root cause. The repo-wide sweep of the same idiom in
`plugins/leadv2/scripts/` was already done by TWELVE-LINUX-ONLY-SUITES-01
group A; the `.5s.sh` widget was missed only because it is not imported by
the renderer that lane tested and `tests/` is outside the core-offline
selection.
