# Lead-authored brief — lane 424569a7 (row `3f44760b3faa`, RUNNER-LEAKS-ITS-LOCK-FLAG-INTO-THE-SUITES-IT-RUNS-01)

This brief exists because the lane was killed mid-build by an explicit founder stop order on
2026-09-15, leaving `build` recorded and no `plan`/`gate1` prefix. It records the plan that was
already settled before the lane started; it is not a re-plan.

## Subject and scope
`plugins/leadv2/scripts/tests/run-core-offline.sh` — the gate runner itself — plus three suites it
selects. Write set is those four files and the lane's report. Nothing else.

## The defect, measured with a paired control before the lane was dispatched
`run-core-offline.sh:179` re-execs itself under `flock` as
`env _LV2_CORE_OFFLINE_LOCK_HELD=1 bash "${BASH_SOURCE[0]}" …`. That variable lands in the
environment of the locked child, and the locked child is the process that runs every suite — so
every suite body inherits it. The guard at `:170-172` then skips the lock whenever it is set.

`test-core-offline-lock-01.sh` is the suite that asserts about that lock. Measured 2026-09-15 on
macOS, same binary, same command, only the environment differing:

```
clean env                        rc=0
_LV2_CORE_OFFLINE_LOCK_HELD=1    rc=1  pass=1 fail=2
  [LOCK-01] (a)/(b) FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired ...>>>
  [LOCK-01] (c)     FAILED rc=0 out=<<<[CORE-OFFLINE] lock-probe acquired ...>>>
```

So the suite can never be green under the gate that selects it. Cause class
`harness_self_interference`. The flag must scope the re-exec, not the suite bodies — while still
letting the re-exec recognise itself as the locked child, or the runner recurses and holds the lock
forever.

## The second question this lane owns
Two more census-red suites are green in every isolated condition tried: `test-dod-gate-suite-
registration.sh` (1s) and `test-shared-sink-test-guard.sh` (2s). Ruled out by measurement: run alone,
run in parallel with each other twice, run under `_LV2_CORE_OFFLINE_LOCK_HELD=1`, run under
`LEADV2_TEST_CONTEXT=1` — green every time. The runner invokes them with a bare `bash <path>`, so the
instrument is identical. The lane finds why they are red under the runner, or states plainly that it
could not and lists what it ruled out. "Probably concurrency" is not an answer.

## Work already on the lane branch
`worktree-3f44760b3faa` carries `2fd2c635` — the interrupted work, committed by the lead after the
stop order with the label `wip: … not reviewed, no controls recorded`. It touches
`run-core-offline.sh` (+11) and `test-core-offline-lock-01.sh` (+1) and leaves a
`.bak_suite_fix` file behind. None of it has been reviewed and no negative control was recorded for
it. The resumed lane owns all of that, including removing the stray `.bak` file.

## Standing rules
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`. In particular: the paired control above must
be re-run as this lane's negative control; anything else changed needs its own; and the runner must
be exercised end to end once, reporting wall time and `SHARD_RESULT` lines, not just the suite.

## Acceptance
```
cd ~/Projects/leadv2 && _LV2_CORE_OFFLINE_LOCK_HELD=1 \
  bash plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh >/dev/null 2>&1
```
Red at dispatch time. It covers the named mechanism only; the two unexplained suites are answered in
the report.
