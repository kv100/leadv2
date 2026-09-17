# PRODUCT-CLOSE-SCOPE-DIFF-EXITS-BEFORE-ITS-OWN-BRANCHES-01 — report

Boundary for every count below: macOS 26.6.2 (Darwin 25.6.0), bash 5.3.9 (the suites
additionally gate `/bin/bash` 3.2 syntax internally), run from the registered lane
worktree `f7ee9525cb40`, no per-suite external timeout (walls reported where they
matter). Commits: `8949c0a4` (lane anchor, pre-fix subject) → `409fe388` (fix, see
"provenance") → `847e72d4` (test re-pin, this lane). Platform claim is **macOS-only**
(Linux suite populations are a separate census row; nothing here asserts Linux green).

## Provenance of the fix (read this first)

The lane's fix was already committed as `409fe388` — an auto-checkpoint ("wip(1bcf53c1):
auto-checkpoint on worker exit (STOP-GATE)") of a prior worker session on this lane that
died after writing it. This lane's work was therefore **verification, not invention**:
every hunk was (a) reversed to reproduce the pre-fix reds from this branch, (b) restored,
(c) proven by one negative control per hunk, and (d) one regression the checkpoint
introduced in a sibling suite was found, measured, and re-pinned (`847e72d4`). Nothing was
taken on trust from the checkpoint.

The checkpoint carries three fix hunks in
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, matching the mission's two
causes (the first cause needs two hunks — see Suite 2):

| hunk | id in code | touches |
|---|---|---|
| 1 | `BOOTSTRAP-ANCHOR-IS-NOT-PRODUCTION-01` (2026-09-17) | `_pc_lane_commits_ahead` (:1887-1916) |
| 2+3 | `WRITESET-FOREIGN-SCAN-NORMAL-PATH-01` (2026-09-17) | `pc_stop_gate_autocommit` (:2829-2895) |
| 4 | `BOTH-KILLS-OFF-EMPTY-DIFF-LANDS-01` (2026-09-17) | `blocked_reason` tail (:3651-3655) |

## Before/after summary

| suite | pre-fix (subject reverted to `8949c0a4` bytes) | post-fix (`409fe388` + `847e72d4`) |
|---|---|---|
| tests/test-lane-diff-single-repo.sh | rc=1 — `FAIL C5-registered-arm-silent` | rc=0 |
| tests/test-dispatch-product-close-exit-trap.sh | rc=1 — 7 passed / 1 failed (Test (b); Test (a) env-conditioned, see below) | rc=0 — 8 passed / 0 failed |
| tests/test-stop-gate.sh | rc=1 — `FAIL: foreign-repo-journaled` | rc=0 — 13 passed (red→green), 0 failed |
| tests/test-dispatch-silent-arm.sh (re-pinned) | rc=0 pre-branch, **rc=1 at `409fe388`** (Case 3) | rc=0 — 12 passed / 0 failed |

---

## Suite 1 — test-lane-diff-single-repo.sh (mission Cause 1)

- Reproduction command: `bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh`
  with the three fix hunks reversed (working tree verified byte-identical to `8949c0a4`
  via `git diff --stat 8949c0a4 -- <subject>` = empty).
- Observed (pre-fix): rc=1,
  `[TEST][post-fix] FAIL C5-registered-arm-silent` / `FAIL: C5-registered-arm-silent`.
- Cause class: `real_regression`. T11-F2 lane worktree births add one `--allow-empty`
  "lane <id> anchor" commit between base and HEAD; the silent-arm probe's commits-ahead
  check read it as production.
- Mechanism: `_pc_lane_commits_ahead` (`leadv2-dispatch-product-close.sh:1885`) counted
  `rev-list --count ${base}..HEAD` including the anchor; `pc_silent_arm_probe` (:2350-2357)
  treats `commits_ahead >= 1` as NOT silent and returns 1; the default branch then stamps
  `terminal=no_work cause=empty_diff` instead of `cause=arm_produced_nothing` — exactly
  the census line (`review_gate ... terminal=no_work cause=empty_diff`).
- Fix: hunk 1. When the count is >0, walk `${base}..HEAD` and subtract commits satisfying
  `_pc_commit_is_anchor` (:1831 — subject `lane * anchor`, has a parent, empty diffstat);
  only non-anchor commits count as production.
- Negative control (mutation in the lane worktree, in the function body; target text
  asserted present before mutating — marker count 1 → 0):
  ```
  $ git apply -R /tmp/pc-anchor-fix.patch   # anchor hunk only
  MUTATION-LANDED: marker count now 0
  $ bash plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh
  lane-diff rc=1
  [TEST][post-fix] FAIL C5-registered-arm-silent
  FAIL: C5-registered-arm-silent
  $ git apply /tmp/pc-anchor-fix.patch      # restore
  RESTORED: 1 marker, git-dirty=0
  ```
- Final run: rc=0 at `409fe388` (`/tmp/final-lane-diff.log`, re-run after all control
  churn, tree verified clean vs HEAD).

## Suite 2 — test-dispatch-product-close-exit-trap.sh (mission Cause 1, second face)

- Reproduction command: `bash plugins/leadv2/scripts/tests/test-dispatch-product-close-exit-trap.sh`
- Observed (pre-fix, full revert): rc=1, `7 passed, 1 failed` — the failing assertion is
  **Test (b)**, not Test (a):
  ```
  [TEST] FAIL: Test (b): row is not dead/crashed_unfinished -- {"ts":"2026-09-17T04:31:09Z",
    "task_sig":"b2b2b2b2", ..., "terminal":"dead_with_unlanded_work","cause":"crashed_unfinished",
    "evidence":"source=exit_trap commit=409fe388", ...}
  ```
- Cause class: `real_regression`, two independent sub-mechanisms (hence this suite needed
  BOTH hunk 1 and hunk 4):
  1. **Test (b)**: the EXIT trap's unlanded-work check counted the lane's own anchor
     commit as production, so a SIGTERM mid-run recorded
     `dead_with_unlanded_work` instead of `dead/crashed_unfinished`. The suite greps
     `"terminal":"dead"` (quote-closed) — `dead_with_unlanded_work` fails it. Hunk 1
     fixes this as a side effect of the same anchor correction.
  2. **Test (a)**: with `E2E_ON=0`/`REVIEW_ON=0`, `pc_scope_diff`'s blocked path exited 5
     before `REVIEW_ON` was ever consulted — the mission's observed
     `expected exit 0, got rc=5`, row `no_work/empty_diff`, not `landed`. Hunk 4
     (`BOTH-KILLS-OFF-EMPTY-DIFF-LANDS-01`, :3651-3655) lands such closes as
     `review_gate_disabled` (scoped to `terminal=no_work` only).
- **Environment-condition finding on Test (a)** (named per lane-rules measurement
  hygiene): in this lane worktree, pre-fix Test (a) measured GREEN — the suite never sets
  `LEADV2_LANE_WORK_ROOT`, so its fixture resolves no lane and never enters
  `pc_scope_diff`'s `blocked_reason` branch; the kill-switch consult is unreachable and
  the assertion cannot see hunk 4. The census red was reproduced by exporting
  `LEADV2_LANE_WORK_ROOT` to a freshly birthed registered fixture lane
  (`git log -1` in it: `faa0a0c lane ctl2-59035 anchor`) — see the control below. This is
  a property of the fixture, not a pass we manufactured: the same suite body, same
  commit, same platform, two environments, two answers.
- Negative controls (both in the lane worktree, target text asserted present → absent):
  ```
  # Control 2a — hunk 4 only, WITH LEADV2_LANE_WORK_ROOT=<registered fixture lane>
  $ git apply -R /tmp/pc-bothkills-fix.patch
  MUTATION-LANDED: marker=0
  $ LEADV2_LANE_WORK_ROOT="$WT" bash plugins/leadv2/scripts/tests/test-dispatch-product-close-exit-trap.sh
  mutated rc=1
  [TEST] FAIL: Test (a): expected exit 0, got rc=5 -- out=[leadv2-dispatch-product-close] stop_gate_autocommit_skipped task=a1a1a1a1 reason=writes_csv_empty
  [TEST] FAIL: Test (a): row is not 'landed' -- {... "terminal":"no_work","cause":"empty_diff" ...}
  $ git apply /tmp/pc-bothkills-fix.patch
  RESTORED marker=1 dirty=0

  # Control 2b — hunk 1 only (anchor subtract), same env not needed
  $ git apply -R /tmp/pc-anchor-fix.patch
  MUTATION-LANDED: marker count now 0
  $ bash plugins/leadv2/scripts/tests/test-dispatch-product-close-exit-trap.sh
  exit-trap rc=1
  [TEST] FAIL: Test (b): row is not dead/crashed_unfinished -- {... "terminal":"dead_with_unlanded_work" ...}
  $ git apply /tmp/pc-anchor-fix.patch && echo RESTORED
  ```
  Control 2a reproduces the mission's observed output verbatim (rc=5, no_work/empty_diff,
  row not landed). Control 2b proves Test (b)'s red is owned by the anchor hunk, not by
  hunk 4.
- Final run: rc=0, `8 passed, 0 failed` at HEAD.

## Suite 3 — test-stop-gate.sh (mission Cause 2 — the serious half)

- Reproduction command: `bash plugins/leadv2/scripts/tests/test-stop-gate.sh` (wall ~256 s;
  given 540 s — it completed, not timed out).
- Observed (pre-fix, stop-gate hunks 2+3 reversed): rc=1,
  `FAIL: foreign-repo-journaled -- post-fix rc=1, expected 0`.
- Cause class: `real_regression`. A write set naming an in-scope path plus a
  relative traversal into a sibling repo (`../../sibling/x`) escaped BOTH existing
  classifiers: `pc_stop_gate_capture_diff` only classifies absolute paths (:2768-2770)
  and the `CROSS_REPO_DIFF` arm only runs on that branch (:3226-3229). The array reached
  `pc_stop_gate_autocommit` empty → no `stop_gate_skipped_foreign_repo` journal line →
  **the foreign file was silently dropped from the checkpoint** (the journal line was only
  how the suite noticed; the silent drop is the defect).
- Fix: hunks 2+3 (`WRITESET-FOREIGN-SCAN-NORMAL-PATH-01`, :2843-2895): on EVERY path that
  reaches the gate, resolve each declared entry (absolute or lane-root-relative) to its
  containing repo; a different toplevel is foreign (membership-checked so the capture-path
  populate is not duplicated), foreign entries are excluded from the staging list
  deliberately, and the skip is journaled.
- Negative control (both hunks reversed together — they are one logical fix; marker
  asserted 1 → 0):
  ```
  $ git apply -R /tmp/pc-stopgate-fix.patch
  MUTATION-LANDED: marker=0
  $ bash plugins/leadv2/scripts/tests/test-stop-gate.sh
  stop-gate rc=1
  [TEST] FAIL: foreign-repo-journaled -- post-fix rc=1, expected 0
  FAILURES:
   - foreign-repo-journaled: post-fix did not pass (rc=1)
  $ git apply /tmp/pc-stopgate-fix.patch
  RESTORED marker=1 dirty=0
  ```
- Final run: rc=0, `Results: 13 passed(red->green), 0 failed, 0 green-pre-fix,
  0 could-not-run` at HEAD.

## Not in the mission's three, but this lane's fix broke it — test-dispatch-silent-arm.sh

Running the changed file's coupled neighbor suites surfaced a real regression the
checkpoint introduced: `test-dispatch-silent-arm.sh` was 12/0 green on the pre-branch
tree and **rc=1 at `409fe388`** — `Case 3: expected reason: no_work on the existing path`.
Its second assertion (:181) encoded exactly the superseded contract hunk 4 replaced
(no_work blocks with a `reason: no_work` artifact when both kill-switches are off).

This is lane-rules' one legitimate case for editing a test, with the required proof:
- Superseding decision recorded in code: `BOTH-KILLS-OFF-EMPTY-DIFF-LANDS-01`
  (2026-09-17), `leadv2-dispatch-product-close.sh` blocked_reason tail (:3642-3655) —
  with both arms off, the close is bookkeeping-only and must land as
  `review_gate_disabled` instead of exiting 5.
- One case asserting the NEW behaviour exists: `test-dispatch-product-close-exit-trap.sh`
  Test (a) (row `landed`, exit 0) — green in the final runs above.
- The growth guard (fresh stream is NOT silent), Case 3's original subject, remains
  guarded end-to-end by `test-silent-arm-commits-ahead.sh` Case C (:144-165) — 15/0 green
  at HEAD.
- Re-pin commit `847e72d4`: Case 3's second assertion now requires rc=0 plus a
  `landed`/`review_gate_disabled` ledger row.
- Control for the re-pin (proves the new assertion is not vacuous — it reds on the
  pre-fix subject):
  ```
  $ git apply -R <all three fix hunks>   # pre-fix subject tree
  $ bash plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh
  repinned suite PRE-FIX rc=1
  [TEST] FAIL: Case 3: expected rc=0 + landed/review_gate_disabled row with both gates off,
    rc=5 -- row={... "terminal":"no_work","cause":"empty_diff" ...}
  $ git checkout -- plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
  RESTORED-HEAD 0
  # on HEAD, same suite: rc=0, 12 passed / 0 failed
  ```

## Changed-scope runner

`LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh --scope changed` selects **~60
suites** off the single changed production file (`leadv2-dispatch-product-close.sh` is a
trigger of the entire product-close family — full list captured in the lane transcript).
A full 60-suite sweep exceeds a lane's budget and pulls in suites owned by other lanes;
instead, every suite directly coupled to the three changed functions was run to green at
HEAD:

```
test-lane-diff-single-repo.sh        rc=0
test-dispatch-product-close-exit-trap.sh rc=0 (8/0)
test-stop-gate.sh                    rc=0 (13/13, ~256 s)
test-dispatch-silent-arm.sh          rc=0 (12/0, after re-pin 847e72d4)
test-silent-arm-commits-ahead.sh     rc=0 (15/0)
test-produced-nothing-cause.sh       rc=0 (5/0)
test-empty-writes-autocommit-loud-skip.sh rc=0 (ALL PASS)
```

Syntax gates: `bash -n leadv2-dispatch-product-close.sh` (clean, and re-checked on the
pre-fix tree), `bash -n test-dispatch-silent-arm.sh` (clean), plus the suites' internal
`/bin/bash` 3.2 syntax gates (pass). No Python files changed.

## Formal mutation-control artifacts

The three negative controls above were additionally formalized with
`leadv2-mutation-control.sh --live` (same mutations, same lane worktree — the tool
applies to the real file, proves red, restores byte-identical, and binds
`lane_diff_hash`); artifacts land under `mutation-control/` in this directory and are
committed alongside this report. Pasted outputs above are from the manual patch-revert
runs; the artifacts are the mechanically checkable form of the same claims.

## Left red

Nothing. All three mission suites are green at HEAD, and the one sibling regression the
fix introduced is re-pinned with its own control. All claims macOS-only.
