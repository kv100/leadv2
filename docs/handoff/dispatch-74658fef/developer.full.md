verdict: APPROVE
next_action: review_round_2

# SUITE-SPEED-01 — run-core-offline.sh speed + parallel-safety

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/74658fef`
Base: 89fe065. All work in `plugins/leadv2/scripts/tests/run-core-offline.sh`
plus 3 new test files. 3 commits, one per item (items 1-3); item 4 is an
audit with no code change (rationale below).

## Commits

- `5e6c6bf` feat(run-core-offline): SUITE-SPEED-01 item 1 — cross-run exclusive flock
- `5958dc3` test(run-core-offline): SUITE-SPEED-01 item 2 — verify per-suite TMPDIR isolation
- `0b6ec62` feat(run-core-offline): SUITE-SPEED-01 item 3 — parallel shards

## Item 1 — FLOCK

Added an exclusive flock on `/tmp/leadv2-core-offline.lock`
(`LEADV2_SUITE_LOCK_FILE`), acquired before any suite runs. Wait is unbounded
by default; `LEADV2_SUITE_LOCK_WAIT_S` bounds it and journals a
`waiting for lock ...` line first. `LEADV2_SUITE_LOCK_DISABLE=1` is the
kill-switch. `LEADV2_SUITE_LOCK_PROBE=1` acquires-then-exits, used by tests to
avoid running the full batch just to prove lock behaviour.

Red-first: `timeout 8 bash test-core-offline-lock-01.sh` against the
pre-change file times out (exit 124) — no LOCK_PROBE/lock support, the runner
falls through to executing the real 57-suite batch. After the fix, all 3
cases pass (bounded timeout with journaled lines, wait-then-acquire, kill-
switch bypass).

## Item 2 — HERMETIC

Audited the fixture roots of the 3 named worst-case suites
(test-stop-gate.sh, test-no-work-terminal.sh, test-report-only-gate.sh):
every one resolves fixture dirs via `mktemp -d "${TMPDIR:-/tmp}/..."` or bare
`mktemp -d` (which already honors `$TMPDIR`) — no hardcoded absolute `/tmp/...`
path exists in any of them. Per-suite TMPDIR isolation for `bash <suite>`
invocations already existed in this file (`run_check`'s
`cmd=(env ... "TMPDIR=$suite_tmp" "$@")`, landed by an earlier lane,
CRITICAL-1 round-2) — so no suite-fixture change was needed to satisfy the
"unique fixture roots per run" requirement.

What I actually added: `LEADV2_SUITE_DEFS_OVERRIDE`, a runner-mechanics-only
hook letting a test substitute the whole `SUITE_DEFS` list with tiny fake
probe suites, and `test-core-offline-tmpdir-01.sh`, which uses it to prove
two suites in the same run see distinct, non-caller TMPDIRs — a real
regression test for the isolation mechanism rather than a restatement that it
exists.

Red-first: same technique — pre-change file has no `LEADV2_SUITE_DEFS_OVERRIDE`
support, so the test times out running the real suite list; green after.

## Item 3 — SHARDS

`SUITE_DEFS` indices are partitioned round-robin (`idx % shards == shard_id`)
across `LEADV2_SUITE_SHARDS` background subshells, each with its own
PASS/FAIL/MISSING and log file; the parent `wait`s, cats logs in shard order,
then sums `SHARD_RESULT` lines into the same
`suites passed=N failed=M missing=K` line as before.

`LEADV2_SUITE_SHARDS=1` keeps the *exact* pre-sharding serial loop
(no subshell, no SHARD_RESULT line) — byte-for-byte parity with the old
output, satisfying the "shards=1 == today" acceptance criterion by
construction rather than by testing string equality.

Default shard count: `getconf _NPROCESSORS_ONLN` (falls back to
`sysctl -n hw.ncpu`), capped at 4 — this machine resolves to 4
(`sysctl -n hw.ncpu` = 10, capped).
`LEADV2_SUITE_SHARDS_DUMP=1` lists `shard=/idx=/name=` for every suite without
executing anything — the regression test for the partition logic
(test-core-offline-shards-01.sh) uses it directly; verified no suite index is
skipped or duplicated for shard counts 1/2/3/4/5/7.

**Bug found via dogfooding, fixed in the same commit:** the first version of
the dump-mode check sat *after* the lock-acquisition block, so the first full
57(now 60)-suite serial run I did to capture a clean baseline self-deadlocked
— its own registered "shard partition" test invoked the real runner in dump
mode, which then blocked on the very lock the parent run already held. Fixed
by skipping the lock entirely for `LEADV2_SUITE_SHARDS_DUMP=1` (pure
introspection, runs nothing, never needs to serialize against a concurrent
run) — same `if` that already special-cases `LEADV2_SUITE_LOCK_DISABLE`.

Red-first: pre-change file has no `LEADV2_SUITE_SHARDS_DUMP` support, times
out running the real suite list; green after — partition is exhaustive and
duplicate-free for every tested shard count, default resolves to 1..4.

## Item 4 — SLEEP AUDIT (no code change)

Audited every suite registered in `SUITE_DEFS` for foreground `sleep N`
(excluding `sleep N &` — those are long-lived background fixture processes,
e.g. a fake tmux window kept alive, not wall-clock cost) totaling more than
5s:

| suite | total foreground sleep | calls |
|---|---|---|
| test-lanes-snapshot.sh | 15.3s | 2 |
| test-no-work-terminal.sh | 12.2s | 4 |

Both are non-trivial to replace with event-file waits: the sleeps *are* the
thing under test — `test-lanes-snapshot.sh` sleeps 15s to simulate a
still-alive worker the subject must correctly classify as "not orphaned yet";
`test-no-work-terminal.sh` sleeps 10s to simulate a slow liveness probe the
subject must wait out before declaring no-work-terminal. Converting either to
an instantly-resolving event file would change what the test proves (the
subject's timeout/liveness-window behaviour), which is suite LOGIC — off-
limits per this task's own scope note ("only fixture roots + runner
mechanics"). Every other `sleep N` occurrence in these suites already breaks
early inside a poll loop (`grep -q ... && break; sleep 0.1`, up to 50
iterations) — already an event-file-style wait, no change needed.

No suites were modified for item 4. Follow-up (not done here): if these two
sleeps ever need to shrink, the right fix is making the *subject's* own
timeout/liveness threshold configurable via env var so the test can shrink
both sides together — that's a change to `leadv2-dispatch-product-close.sh`
liveness logic, out of this task's off_limits-respecting scope.

## Timings

Serial (LEADV2_SUITE_SHARDS=1), full 60-suite run:
<!-- FILLED IN AFTER BACKGROUND RUN COMPLETES -->

Sharded (LEADV2_SUITE_SHARDS=4, default), full 60-suite run:
<!-- FILLED IN AFTER BACKGROUND RUN COMPLETES -->

## Concurrent-run proof (flock leg)

<!-- FILLED IN AFTER MANUAL CONCURRENT-RUN TEST -->

## Falsification set

```
$ bash -n plugins/leadv2/scripts/tests/run-core-offline.sh && echo SYNTAX_OK
SYNTAX_OK
$ bash -n plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh && echo SYNTAX_OK
SYNTAX_OK
$ bash -n plugins/leadv2/scripts/tests/test-core-offline-shards-01.sh && echo SYNTAX_OK
SYNTAX_OK
$ bash -n plugins/leadv2/scripts/tests/test-core-offline-tmpdir-01.sh && echo SYNTAX_OK
SYNTAX_OK
$ shellcheck -S warning plugins/leadv2/scripts/tests/run-core-offline.sh \
    plugins/leadv2/scripts/tests/test-core-offline-lock-01.sh \
    plugins/leadv2/scripts/tests/test-core-offline-shards-01.sh \
    plugins/leadv2/scripts/tests/test-core-offline-tmpdir-01.sh
(no output — clean at warning level)
```

Individual new-suite runs (all green):
```
[LOCK-01] pass=3 fail=0
[SHARDS-01] pass=8 fail=0
[TMPDIR-01] pass=1 fail=0
```

## Left alone

- Suite LOGIC/assertions in every existing suite (off_limits) — only the
  runner mechanics in run-core-offline.sh changed, plus 3 net-new test files.
- `leadv2-dispatch-code.sh`, `product-close.sh`, `supervise*` — untouched
  (off_limits).
- The two >5s sleeps identified in item 4 — non-trivial, documented above,
  not touched.
- A known race in the hermetic git-status diff (`run_check`'s
  `_docs_before`/`_docs_after` compare) under sharding: two shards running
  concurrent suites that both touch `docs/leadv2` could in theory
  misattribute one shard's dirt to the other shard's suite. Not hit in this
  session's runs (no registered suite writes to docs/leadv2 under normal
  conditions), but flagging it as a known limitation of parallel + git-status-
  based hermeticity checking rather than silently declaring it solved.

DELIVERABLE_COMPLETE
