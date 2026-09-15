# RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01

Row `3f44760b3faa`. Subject: `plugins/leadv2/scripts/tests/run-core-offline.sh` — the gate runner
itself.

**Read `docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md` first and follow it.**

## The defect, already measured with a paired control by the lead
`run-core-offline.sh:179` re-execs itself under `flock` as:

```bash
flock -x -n -E 99 -o "$LEADV2_SUITE_LOCK_FILE" \
  env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash "${BASH_SOURCE[0]}" ...
```

`_LV2_CORE_OFFLINE_LOCK_HELD=1` is placed in the environment of the locked child, and that child is
the process that runs every suite — so **every suite body inherits the flag**. The guard at
`:170-172` skips the lock whenever it is set.

`test-core-offline-lock-01.sh` is the suite that asserts about that very lock, so under the gate it
always finds the lock already taken. Measured 2026-09-15, macOS Darwin 25.6.0, same binary, same
command, only the environment differing:

```
clean env                              rc=0
_LV2_CORE_OFFLINE_LOCK_HELD=1          rc=1   pass=1 fail=2
  [LOCK-01] (a)/(b) FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=.../lv2-lock-test.gl2a0r>>>
  [LOCK-01] (c)     FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired file=.../lv2-lock-test.gl2a0r>>>
```

So this suite **can never be green under the runner that selects it.** It is a permanent false red,
counted against every lane, for a subject that is not broken. Cause class:
`harness_self_interference`.

## The fix, and the thing to be careful about
The flag must scope the **re-exec**, not the suite bodies. Unsetting it around suite invocation is
the obvious direction. Be careful that you do not break what it is there for: the re-exec must still
recognise that it is the locked child, or the runner will recurse and take the lock forever. Show
that you checked this — run the runner itself at least once end to end and report the wall time and
the `SHARD_RESULT` lines, not just the suite.

Also confirm the same leak does not exist for the other variables in that block
(`LEADV2_SUITE_SHARDS_DUMP`, `LEADV2_CORE_OFFLINE_SCOPE_DUMP`, `LEADV2_TEST_CONTEXT` exported at
`:131`). Report what you found for each — including "no leak" — rather than only what you fixed.

## The second, open question this lane must also answer
Two more suites are red in the census and **green in every isolated condition tried so far**:

```
test-dod-gate-suite-registration.sh   alone rc=0 (1s)
test-shared-sink-test-guard.sh        alone rc=0 (2s)
```

Both are far under the census's 120s ceiling, so time does not explain them. Already ruled out by
the lead, by measurement: running the two plus `test-core-offline-lock-01.sh` in parallel with each
other (twice, all green), `_LV2_CORE_OFFLINE_LOCK_HELD=1` (both green), `LEADV2_TEST_CONTEXT=1`
(both green). The runner invokes them with a bare `bash <path>` and no extra arguments, so the
instrument is identical.

**Find out why they are red under the runner and not outside it, or state plainly that you could
not and what you ruled out.** "Probably concurrency" is not an answer; a named co-scheduled suite,
a shared path, or a shared journal is. `test-shared-sink-test-guard.sh` exists to catch tests
polluting the real journal, which is a strong hint about where to look — but it is a hint, not a
finding, and you must not report it as one.

Do not make either suite green by any means other than removing the interference. If the honest
answer is "these two are flaky under load", say that, with the number of runs behind it.

## Write-set note
Your write set covers the runner and the three suites. If the interference turns out to live in a
file you cannot write, stop, name the file, and report it. Do not work around the write set.

## Deliverables
- The leak fix, with the paired control above re-run (clean vs flag-set) as your negative control.
- A separate control for anything else you change.
- `docs/handoff/RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01/report.md` per
  `lane-rules.md`, including a section on the two unexplained suites with what you ruled out.

## Acceptance
```
cd ~/Projects/leadv2 && _LV2_CORE_OFFLINE_LOCK_HELD=1 \
  bash plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh >/dev/null 2>&1
```
Red today (rc=1). This probe covers the named mechanism only; the two unexplained suites are
answered in the report, not by this command.
