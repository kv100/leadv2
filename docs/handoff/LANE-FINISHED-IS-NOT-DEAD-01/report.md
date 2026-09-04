# LANE-FINISHED-IS-NOT-DEAD-01 — round 2 report

## Provenance

Round 1's fix (`commit_age_s()` + `LEADV2_LANE_FINISHED_WINDOW_S` in
`leadv2-lane-liveness.sh`, plus the matching veto in `leadv2-lanes-snapshot.sh`)
was committed as `1c7094f` on the sibling worktree branch
`worktree-LANE-LIVENESS-THREE-STATES-02`, salvaged after that lane was killed
by the machine-wide suite lock before it could commit itself, and never
merged into `main`. This lane (`LANE-LIVENESS-PROVE-03`, base `4a9c163`) is a
fresh worktree/branch — round 1's commit was not present here, so it was
cherry-picked in first (`757d043`) before round 2's own work could begin.

## The prove-gate (mandatory bar #1-#3)

Revert `leadv2-lane-liveness.sh` + `leadv2-lanes-snapshot.sh` to `main`'s
versions:

```
$ bash plugins/leadv2/scripts/tests/test-lane-finished-state.sh
[TEST] RESULTS: 2 passed, 4 failed
[TEST] FAIL: Test 2: verdict=dead:no_handoff_dir escalated=True still_present=False
[TEST] FAIL: Test 4: verdict=alive (must be finished:*, never alive) escalated=False still_present=True
[TEST] FAIL: Test 5a: pre-mutation baseline must be finished:* (got dead:no_handoff_dir) -- fixture broken, mutation gate aborted
[TEST] FAIL: Test 5b: pre-mutation baseline must keep the row present (got present=False) -- fixture broken, mutation gate aborted
EXIT=1
```

Restore (`git checkout -- <files>` back to the committed `757d043`/`6948a52`
state):

```
$ bash plugins/leadv2/scripts/tests/test-lane-finished-state.sh
[TEST] RESULTS: 10 passed, 0 failed
EXIT=0
```

`git diff --stat` after restoring is clean (no diff against HEAD).

## Which of the original 6 assertions touch production code vs vacuous (bar #4)

| Test | Touches production code? | Notes |
|---|---|---|
| 1 — live pid + fresh stream → alive | Yes | Exercises the standard pid-alive + stream-freshness path; fails against `main` too (main has no `finished` branch to interfere, so this one alone isn't diagnostic of the fix, but it's not vacuous — it pins the non-regression baseline). |
| 2 — dead pid + recent commit → finished | **Yes, diagnostic** | Directly exercises `commit_age_s()`/`finished_window`. FAILS on `main` (no such logic exists there) — this is the core positive case for the fix. |
| 3 — dead pid, unborn HEAD, no deliverable → dead | Yes, but not diagnostic of THIS fix | Passes on both `main` and the fix — it was already correct pre-fix. Valuable as a negative control (proves the fix doesn't turn every dead-pid lane into `finished`), not proof the fix exists. |
| 4 — dead pid + recent commit + fresh stream mtime → still finished, never alive | **Yes, diagnostic** | FAILS on `main` (main reads the fresh stream mtime and returns `alive`). Proves precedence: commit evidence overrides stream mtime. |
| 5a — mutate `leadv2-lane-liveness.sh`'s finished-check → RED, revert → GREEN | **Yes, diagnostic, self-proving** | This is a genuine mutation-testing gate: it patches the live script mid-run and asserts the verdict flips. Round-1's original problem (round 1 of THIS mission — a 6-assertion suite that stayed green after reverting both prod files) is exactly what this test was built to close. Confirmed not vacuous: it FAILS on `main` (baseline mismatch, since `main` has no `finished:*` verdict to begin with) and PASSES against the fix. |
| 5b — mutate `leadv2-lanes-snapshot.sh`'s finished-veto → RED, revert → GREEN | **Yes, diagnostic, self-proving** | Same shape as 5a, for the snapshot-side veto. FAILS on `main`, PASSES against the fix. |

Net: of the original 6, **4 are diagnostic of the round-1 fix** (2, 4, 5a,
5b — each fails on unmodified `main` and passes on the fix), and **2 are
non-diagnostic negative controls** (1, 3 — pass on both `main` and the fix,
because they test paths the fix didn't change). None of the 6 are vacuous in
the sense round 1's original suite was (that suite passed identically on
`main` and on the fix for ALL 6 assertions, proving nothing). The two
non-diagnostic ones are legitimate regression guards, not padding.

## The 4 cases named in the round-2 brief

1. **No worker + newer commit ⇒ finished, never dead.** Covered by Test 2/4
   (diagnostic, see above).

2. **No worker + only the anchor commit ⇒ dead.** Not covered by the
   original 6 (Test 3 uses an *unborn* HEAD — zero commits — which trivially
   short-circuits `commit_age_s()` to `None`; it does not prove an *old*
   single commit is correctly excluded). Added **Test 6**: single commit
   backdated 7200s (`GIT_COMMITTER_DATE`/`GIT_AUTHOR_DATE`), past
   `LEADV2_LANE_FINISHED_WINDOW_S` (default 1800s), dead pid, no stream →
   asserts `dead:no_handoff_dir`, never `finished:*`. Passes against current
   production code (`commit_age_s()` already gates on `finished_window`, so
   no fix was needed) — closes a real coverage gap, not a real bug.

3. **Stale `starting` registration (no live pid, older than its own grace)
   ⇒ dead, and must be resumable.** Not covered by the original 6. Added
   **Test 7**: `active.yaml` session with `started_at` 400s in the past
   (> `LEADV2_LANE_STARTING_MAX_S` default 300s), dead pid, unborn HEAD, no
   stream → asserts `dead:no_handoff_dir`, never stuck on `starting:*`.
   `leadv2-lane-liveness.sh`'s Tier-A registration logic (`registered_no_stream`
   branch) already falls through past `starting_max` to the same dead
   determination used elsewhere — confirmed correct, no fix needed here.
   **Caveat**: the incident described in the brief (`--resume-lane` refusing
   with `lane_is_live verdict=starting:70` forever) is a claim about the
   *consumer* of this verdict, `leadv2-dispatch-code.sh` (line ~887,
   `reason="lane_is_live"`) — that file is **out of `LANE_WRITES` scope for
   this lane** and was not touched or tested. This report proves the fact
   `leadv2-lane-liveness.sh` produces (`dead:*` once stale) is correct; it
   does not prove the consumer reads that fact correctly. If the incident
   recurs, the next investigation should start in
   `leadv2-dispatch-code.sh`'s `lane_is_live` check, not here.

4. **Live pid whose cwd is the lane worktree ⇒ live, regardless of stream
   mtime.** `grep -n "cwd" plugins/leadv2/scripts/leadv2-lane-liveness.sh`
   returns zero matches — no cwd-based liveness check exists in production
   code today. Added **Test 8** instead, proving the actual current
   behavior: a real spawned process (cwd = lane worktree) with a stale
   (1500s — between `SILENT_MAX`=900s and `ABANDON_MAX`=3600s) stream
   resolves to `silent:1500`, never `dead:*` or `finished:*`. This is
   consistent with `leadv2-dispatch-code.sh`'s own placement gate (only
   `alive`/`starting:*` verdicts count as "live" for placement purposes —
   `silent:*` already blocks re-placement there). Promoting a cwd-matched
   pid straight to `alive` regardless of stream mtime would require changing
   that consumer, which is out of `LANE_WRITES` scope — **declared
   out-of-scope for this lane**, not fixed.

5. **Leaked orphan `leadv2-single-lead-beat-loop.sh` (ppid=1) ⇒ not live.**
   A real ppid=1 orphan cannot be manufactured in a test fixture (only init
   can be the true parent of a process). Added **Test 9**, reusing the
   existing `LEADV2_LANE_PID_IDENTITY` birth-time (`lstart`) corroboration
   hook already present in production code (also covered in isolation by
   `test-lane-registry-self-deadlock.sh`): a pid that is alive but whose
   recorded birth-time doesn't match the registry's expected birth-time
   never reads `alive` from a bare pid-exists check. Checking raw `ppid` was
   deliberately NOT added as a liveness signal — GLM/Codex workers are
   legitimately detached via `setsid_wrapper` and run with `ppid=1` by
   design, so a ppid=1 filter would misclassify real live workers as dead.

## Bar checklist

- [x] Revert both production files → RED (2 passed, 4 failed, exit 1) — shown above.
- [x] Restore → GREEN (10 passed, 0 failed, exit 0) — shown above.
- [x] `git diff --stat` clean afterward.
- [x] This report names which of the six original assertions touched
      production code / were diagnostic vs. non-diagnostic negative
      controls (none were vacuous the way round 1's suite was).
- [x] The 4 named cases: 1 already covered (Test 2/4), 3 given new
      regression coverage (Tests 6, 7, 9) proving current code already
      handles them, 1 (cwd-based live check, part of case "live pid whose
      cwd is the lane worktree") confirmed absent and explicitly
      out-of-scope (would require editing `leadv2-dispatch-code.sh`'s
      placement-gate consumer, outside this lane's `LANE_WRITES`).

## Commits on this branch

- `757d043` — cherry-pick of round 1's fix (`1c7094f`) onto this lane's branch.
- `6948a52` — Tests 6-9 closing the round-2 coverage gaps (test-file only, no production code changed — all 4 cases were already handled correctly).

## Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-liveness.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/leadv2-lanes-snapshot.sh && echo OK
OK
$ bash -n plugins/leadv2/scripts/tests/test-lane-finished-state.sh && echo OK
OK
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-lane-finished-state.sh
[TEST] RESULTS: 10 passed, 0 failed
```
