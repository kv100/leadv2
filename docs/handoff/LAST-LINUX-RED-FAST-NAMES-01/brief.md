# LAST-LINUX-RED-FAST-NAMES-01

One suite stands between this repo and a green CI gate, and therefore between it and required
status checks on `kv100/leadv2` (`SD-CI-REQUIRE-STATUS-CHECKS-01`). This is that suite.

## Measured

CI run `33712162153`, ubuntu-latest, commit `ca99326b` — the gate's own summary line:

    ci-gate: scope=changed run_all_rc=1 known_red=14 unexpected=1
    ci-gate: FAIL — the following suites failed and are NOT on the known-red allow-list:
      - path:tests/test-status-surface-fast-names.sh

Everything else is green or consciously allow-listed. The 83-suite core-offline sweep in the same
run is `passed=69 failed=15` with **zero** outside the allow-list — the macOS baseline exactly.

The same suite on this Mac, same commit: `rc=0`, `12 passed, 0 failed`. Verified by the lead
2026-09-03T03:55Z. So it is a platform difference, not a regression.

The three Linux failures, verbatim from the run:

    FAIL - warm cache   (title='/home/runner/work/leadv2/leadv2/plugins/leadv2/scripts/lead…
    FAIL - stale cache  (title='/home/runner/work/leadv2/leadv2/plugins/leadv2/scripts/lead…
    FAIL - rename hygiene (bashpath='' out=/home/runner/work/leadv2/leadv2/plugins/leadv2/…

On macOS the corresponding T5 assertion passes with a full absolute path in the value, so the
assertions are not simply "expects a short name". Read the CI log for the untruncated values
before forming a hypothesis — do not guess from these elided lines.

## How to work this

`TWELVE-LINUX-ONLY-SUITES-01` just fixed eleven sibling suites and its report
(`docs/handoff/TWELVE-LINUX-ONLY-SUITES-01/report.md`) lists the seven root causes it found. Read
it first — the odds are good that this is an eighth instance of one of them rather than something
new. The largest was subtle and is worth restating: `stat -f %m || stat -c %Y` never falls through
on GNU, because GNU `stat -f` *succeeds* as a filesystem dump, so the substitution captures that
dump. `bashpath=''` in the third failure has that shape — a command that "succeeded" into the
wrong thing, or a lookup that resolves differently under a merged-usr `/bin -> /usr/bin`.

Note the suite lives in `tests/`, not in the core-offline set. That is exactly why it was not
among the twelve: the core-offline sweep never selected it, and only `run-all --scope changed`
does. Check whether other `tests/`-level suites have the same untested-on-Linux exposure and say
so in the report — if there is a second one, we would rather learn it now than one CI run at a
time.

## Definition of done

1. `tests/test-status-surface-fast-names.sh` green on Linux. Proof is a container run
   (`ubuntu:24.04` or `python:3.12-slim`, as the sibling lanes used) with the exit code pasted,
   and still green on macOS — the same verdict on both platforms, not a lower bar on one.
2. Name the root cause and the file:line you changed. If it is one of the seven from
   `TWELVE-LINUX-ONLY-SUITES-01`, say which — that is a useful fact, not a demerit.
3. A negative control: restore the platform-dependent form, show the suite goes red, revert, show
   green.
4. Nothing may be added to `tests/known-red-suites.txt`. This is a fresh platform bug, and hiding
   one there is the lying-green disease this repo has an explicit rule against. If you conclude
   the suite genuinely cannot run on Linux, make it SKIP cleanly on non-Linux with a stated
   reason the way `test-status-surface-bash32.sh` does, and justify it in the report.
5. Do not weaken an assertion to make it pass.
6. Commit in this lane before you finish.

Off limits: `main`, `tests/known-red-suites.txt`, and weakening assertions.
