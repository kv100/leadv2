# ANTI-SILENCE-BEAT-ABORT-03 — round 2 fix

## Worktree/lane mismatch encountered first

The dispatched mission named `LANE ROOT: .../worktrees/ANTI-SILENCE-ONE-MECHANISM-01`, but the
WORKTREE PIN and the actual harness cwd were `.../worktrees/ANTI-SILENCE-BEAT-ABORT-03`. That
worktree's branch (`worktree-ANTI-SILENCE-BEAT-ABORT-03`) had unrelated history (writeset-registry
work) and had diverged from main *before* round 1 (`b2175f6`) and the bash-3.2 heredoc fix
(`67f8b8d`) landed — confirmed via `git merge-base --is-ancestor`. Per the WORKTREE PIN's explicit
"do NOT cd to the main checkout even if the mission text names it," I worked in
ANTI-SILENCE-BEAT-ABORT-03 and rebased it onto local `main` (de44cc7, matching the task binding's
stated base) with `git rebase --autostash de44cc7`. One conflict surfaced on
`docs/leadv2/questions` (a runtime symlink to shared leadv2 state, untracked in main) — resolved
by removing it from the index to match HEAD; left as an untracked working-tree file, unrelated to
this mission's scope.

## Root cause (found from the runtime, not a hypothesis)

Reproduced the exact failure with `bash -x` / `PS4='+L${LINENO}: '` against a bad-collector stub
that writes non-JSON. Trace showed execution stopping dead at line 1290
(`RENDER_JSON="$(python3 ... )"`) — the very next traced line was the EXIT trap's `rm -rf
$RENDER_TMPDIR`. `RC=$?` on the following line never executed.

`leadv2-broad-status.sh` sets `set -uo pipefail` (line 22) — no `-e`. But at line 69 it does:

```
LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" source "${ACTIVE_REGISTRY_SH}" 2>/dev/null || true
```

`leadv2-active-registry.sh` itself sets `set -euo pipefail` (its line 45) — documented in its own
comments as intentional for ITS callers (e.g. leadv2-queue-release.sh). Because `source` runs in
the *current* shell, not a subshell, this permanently turns errexit ON for the rest of
leadv2-broad-status.sh. The `|| true` on the source statement only guards that one statement's own
exit status — it does nothing to undo the `-e` the sourced file just switched on.

Once errexit is live, the render step's `RENDER_JSON="$(python3 render.py ...)"` failing (uncaught
JSONDecodeError, python3 exits 1) kills the whole script immediately via the EXIT trap — before
`RC=$?`, before the `if [[ $RC -ne 0 ]]` check, before `_write_degraded_status` /
`_emit_ready_line` / `_emit_fail_line` ever run. The handling code at line ~1292-1301 that *looks*
correct (and is, in isolation) was simply unreachable. Result: a beat fires, produces zero output —
no artifact write, no LOG_FILE line, no ready line, no failure line. Exactly the founder's
complaint, reproduced live.

## Fix

`plugins/leadv2/scripts/leadv2-broad-status.sh`:

1. Added `set +e` immediately after the `source "${ACTIVE_REGISTRY_SH}"` line, restoring the
   script's own error-handling contract (manual `$?` checks) for everything downstream — the
   render-failure path, the collector-failure path, and any future abort path added there.
2. Changed the render-failure LOG_FILE line (`printf '%s [BROAD_STATUS] render failure...'`) to
   stamp with `$BEAT_AT` instead of `$(_now_iso)`, matching every sibling beat-identity line (round
   1 already unified the *artifact's* line 1 onto `$BEAT_AT`; this internal log line was still on
   wall-clock time).

Diff: `git diff --stat` → `plugins/leadv2/scripts/leadv2-broad-status.sh | 13 ++++++++++++-` (1
file changed, 12 insertions, 1 deletion). Committed as `35f2ac3` on
`worktree-ANTI-SILENCE-BEAT-ABORT-03`.

## Verification

### Target suite — RED before, GREEN after

```
$ bash plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh   # before fix (on rebased main)
[TEST] PASS: T1 ... T2 ...
[TEST] FAIL: T3a: stamp mismatch: at= line1=
[TEST] PASS: T3b ... T4 ... T5
test-beat-stamp-agreement: 5 passed, 1 failed

$ bash plugins/leadv2/scripts/tests/test-beat-stamp-agreement.sh   # after fix
[TEST] PASS: T1: happy path — ready-line at= == artifact line-1 stamp
[TEST] PASS: T2: degraded path — ready-line at= == artifact line-1 stamp
[TEST] PASS: T3a: render failure — ready-line at= == artifact line-1 stamp
[TEST] PASS: T3b: unwritable artifact — FAILED line, no path= token
[TEST] PASS: T4: degraded beat names live lanes, not just staleness
[TEST] PASS: T5: zero live lanes — beat still emits a truthful fact
test-beat-stamp-agreement: 6 passed, 0 failed
```

### Mutation kill proofs (both required by the mission)

**Mutation A — remove the new `set +e` fix → RED, exit code 1:**
```
[TEST] FAIL: T3a: stamp mismatch: at= line1=
test-beat-stamp-agreement: 5 passed, 1 failed
$? = 1
```
Reverted → GREEN, `$? = 0`, diff --stat back to the expected 12-insertion/1-deletion size.

**Mutation B — round 1's control, `lane_facts="$(_live_lane_facts)"` → `lane_facts=""` → RED, exit
code 1** (this must ALSO still fail with my fix in place, proving I did not weaken round 1):
```
FAIL: T5: zero-lane beat produced no lane-fact line: ...
живые линии: недоступно
$? = 1
```
Reverted → GREEN again, `$? = 0`.

### Suite-alone kill confirmed

Both mutations were run with ONLY `test-beat-stamp-agreement.sh` invoked directly — the suite alone
goes red on each mutation and the exit code follows ($?=1 both times), satisfying "a kill counts
only if this suite alone goes red" and "a FAIL: line that leaves $? at 0 is not an assertion."

### Full changed-scope run (`tests/run-all.sh --scope changed`, `LEADV2_SUITE_LOCK_WAIT_S=90`)

`13 passed, 2 failed, scope=changed`:

- `run-core-offline.sh` — FAILED with `FATAL lock_timeout ... wait_s=90`. This is the cross-run
  flock (SUITE-SPEED-01) timing out because ~7 other leadv2 lanes are concurrently active on this
  machine right now (per the session's own active-sessions list) — infrastructure contention, not
  a regression from this diff; unrelated to leadv2-broad-status.sh content entirely.
- `test-broad-status-duty.sh` — FAILED, but investigated against baseline (see below): this is a
  **strict improvement**, not a regression.
- `test-beat-stamp-agreement.sh` — included in this run and PASSED (part of the 13).

### test-broad-status-duty.sh baseline check (mandatory per "never weaken a fixture to get green")

Reverted `leadv2-broad-status.sh` to `git show HEAD:...` (pre-fix, committed state) via a temp-file
swap (no stash), re-ran the suite directly:

```
HEAD (pre-fix):  23 passed, 15 failed
  ... includes ALL FIVE T9b render-failure assertions failing:
  FAIL: T9b: previous healthy table still in founder-status.md
  FAIL: T9b: no СТАТУС НЕ СОБРАН sentence
  FAIL: T9b: pinned beat timestamp missing
  FAIL: T9b: line 1 lacks degraded=1: ...
  FAIL: T9b: failure reason missing from the table row
  (plus T3a/T3b, T4a-T4f, T7, T8b — unrelated to this fix)

With fix restored:  28 passed, 10 failed
  ... all five T9b assertions now PASS.
  Remaining 10 failures (T3a/T3b, T4a-T4f live-loop timing waits of 60-150s,
  T7, T8b doc-wording drift check) are IDENTICAL in both runs — pre-existing,
  environment-sensitive (live supervisor-loop process / doc content), not
  touched by this diff.
```

Restored the fix (`cp` from a saved copy, verified `git diff --stat` matches the committed 12/1
line-count exactly, `bash -n` clean) before committing.

### Self-check (bash -n / py_compile / changed-scope runner)

```
$ bash -n plugins/leadv2/scripts/leadv2-broad-status.sh
(no output — syntax OK)
```
No Python files were touched (`py_compile` — n/a).
Changed-scope runner output: see "Full changed-scope run" above (13 passed, 2 failed — both
explained as pre-existing/infra, not this diff).

## Deliberately left alone

- `docs/leadv2/questions` untracked symlink drift — pre-existing runtime artifact, not in
  LANE_WRITES, not touched.
- `run-core-offline.sh` lock-contention failure — infra (concurrent lanes), not code; no action
  taken, flagged for lead awareness only.
- `test-broad-status-duty.sh`'s remaining 10 failures (T3/T4 live-loop timing, T7, T8b doc drift) —
  confirmed pre-existing on HEAD, out of this mission's scope (mission's suite is
  test-beat-stamp-agreement.sh specifically).
- Did NOT touch `leadv2-active-registry.sh`'s own `set -euo pipefail` — it's documented as
  intentional for its other callers; the leak is on the sourcing side, fixed there instead.
- Did not extend the `$BEAT_AT` stamp fix to the collection-failure log line (line ~231, same
  `$(_now_iso)` pattern) — the mission named only the render-failure line (~1293); leaving the
  sibling line alone per "do exactly what was asked, no drive-by refactors." Worth a follow-up if
  the lead wants full consistency.

DELIVERABLE_COMPLETE
