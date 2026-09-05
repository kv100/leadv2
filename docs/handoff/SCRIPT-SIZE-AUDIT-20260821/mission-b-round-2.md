# Mission B round 2 — the trace exists, its tests do not

Repo: ~/Projects/leadv2. Continue in the EXISTING lane worktree
`.claude/worktrees/f72c8c9c`. Do not restart and do not redesign — round 1's
instrument is sound; it is untested.

## What round 1 actually landed (verified by the lead, not claimed by the worker)

Commit `61b2fd3` is a STOP-GATE checkpoint: the worker died at turn 111 with
`is_error: true`, so it never wrote a report. Its contents:

```
plugins/leadv2/scripts/lib/leadv2-trace.sh        | 198 ++++
plugins/leadv2/scripts/leadv2-trace-report.sh     | 136 ++++
plugins/leadv2/scripts/codex-task.sh              |   4 +
plugins/leadv2/scripts/glm-coder.sh               |  22 +-
plugins/leadv2/scripts/kimi-coder.sh              |  22 +-
plugins/leadv2/scripts/leadv2-backlog-pump.sh     |   7 +
plugins/leadv2/scripts/leadv2-dispatch-code.sh    |   7 +
plugins/leadv2/scripts/leadv2-lanes-snapshot.sh   |   3 +
plugins/leadv2/scripts/leadv2-review-run.sh       |   8 +
plugins/leadv2/scripts/leadv2-router.sh           |   3 +
plugins/leadv2/scripts/leadv2-status-collector.sh |   3 +
                                     11 files, 409 insertions(+), 4 deletions(-)
```

All nine declared seams are instrumented. **`plugins/leadv2/scripts/tests/test-leadv2-trace.sh`
does not exist** — mission item 7 was never done, and item 4's cost claim was never proven.

## Do — tests only, plus whatever minimal product fix a test exposes

1. **Writer schema.** Assert one NDJSON object per span carrying every required field:
   `trace_id, span, script, pid, ppid, t_start_ns, t_end_ns, duration_ms, exit_code,
   child_exec_count`. Assert timings come from a MONOTONIC source — a test that moves
   wall-clock backwards (or stubs `date`) must not corrupt `duration_ms`.
2. **Append under concurrency.** N>=20 concurrent writers into one trace file; assert
   every line is valid standalone JSON and no record is interleaved or truncated.
   This is the property `O_APPEND` single-line writes are supposed to guarantee — test
   it, do not assume it.
3. **OFF costs nothing — the load-bearing one.** With `LEADV2_TRACE` unset, run a
   dispatch resolve-only path (`LEADV2_DISPATCH_SPAWN=0`) and assert **zero** trace
   files are created anywhere under the state dir. Then assert the off-path spends no
   subshell / no external command / no file open per span — inspect the emitted code
   path, or count `execve`-equivalents, and say in the report exactly how you proved it.
4. **Reader.** `leadv2-trace-report.sh` against a fixture trace dir: p50/p95 per span
   name and the per-lane total. Include a fixture with a single sample and one with an
   even sample count, so the percentile arithmetic is pinned.
5. Wire the suite into `run-core-offline.sh` the way its siblings are wired.

If a test exposes a genuine defect in `lib/leadv2-trace.sh`, fix that defect — minimally.
Do not extend the trace to new seams, do not change the record shape to make a test easier,
and do not optimise anything: this mission builds the instrument, it does not use it.

## Off-limits
- Do not touch the nine instrumented call sites except to fix a proven defect.
- Do not touch main's unrelated uncommitted files: no stash/reset/clean.
- Do not merge anything.

## Verify (real pasted output, FOREGROUND, with an explicit timeout)
1. `bash plugins/leadv2/scripts/tests/test-leadv2-trace.sh` — every case.
2. `bash plugins/leadv2/scripts/tests/run-core-offline.sh` — counts + exit code.
   Exactly TWO failures are known-foreign and NOT yours: `deferred-GLM ladder
   (V3-GLM-LADDER-01)` and `fanout classifier/runner guard` (the latter fails because
   `leadv2-fanout.sh:52` sources a file absent from the harness's private HOME). A third
   failure is yours: name it and fix it.

## Deliverable
`docs/handoff/SCRIPT-SIZE-AUDIT-20260821/report-b.md` — the four test groups with pasted
output, how you proved the OFF path is free, `git diff --stat`, and any product defect a
test exposed. End with DELIVERABLE_COMPLETE.
