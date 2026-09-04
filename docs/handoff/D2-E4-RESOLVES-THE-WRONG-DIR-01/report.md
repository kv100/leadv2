# D2-E4-RESOLVES-THE-WRONG-DIR-01 — fix round 2 (+ round 2b found by the live check)

## What shipped

Round 1 (7de54f50 + d072d785): `deliverable_dirs()` resolves the lane's real handoff
dir — the tid-named dir plus the parent of the registry row's own `log_path` when it is
a direct child of `docs/handoff/`. An existing-but-unreadable candidate dir is
`unknown:deliverable_dir_unreadable`, never `dead:`.

Round 2b (5a6b0de2 + b4ad89d9), found by the live check demanded by this brief: the
live D3 lane still read `dead:no_log_artifact` after round 1, because
`sessions = {task_id: row}` keeps only the **last** registry row per lane, and D3's
last row carries no `log_path` at all while its dispatch pointer (`dispatch-57a94876/`,
deliverable on disk) lives on an earlier row. `deliverable_dirs()` now unions **every**
row the registry holds for the task_id (`sessions_all`). Attribution stays exact: every
pointer comes from this lane's own row; still no glob across `docs/handoff/`.

## Ten consecutive suite runs (17 cases)

```
run 1: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 2: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 3: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 4: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 5: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 6: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 7: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 8: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 9: rc=0 [TEST] RESULTS: 17 passed, 0 failed
run 10: rc=0 [TEST] RESULTS: 17 passed, 0 failed
```

Suite: `plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh`, run from the
lane HEAD (b4ad89d9). New cases this lane: Test 10 (founder id → dispatch-dir
deliverable → `finished_unlanded:*`), Test 11 (no deliverable anywhere → `dead:*`),
Test 12 (chmod-000 dispatch dir → `unknown:*`), Test 13 (two registry rows, pointer
only on the non-last row → `finished_unlanded:*`).

## Live checks (the real tool, real lanes, 2026-09-04 ~03:5x)

Lane with a running worker (pid verified alive by `ps` in the same probe):

```
$ ps -p 31321 -o pid,command | tail -1 | cut -c1-60
31321 claude -p \012You are a senior engineer working on the
$ bash plugins/leadv2/scripts/leadv2-lane-liveness.sh --project-root ~/Projects/leadv2 --lane D4-NO-PATH-LOSES-WORK-01
silent:1119

$ bash plugins/leadv2/scripts/leadv2-lane-liveness.sh --project-root ~/Projects/leadv2 --lane LAND-PATH-IS-BROKEN-01
finished:1040s
```

Neither is `dead:*`. D4's worker was alive at probe time (verdict `silent:1119`,
pid_source=worker); LAND-PATH resolved `finished:1040s` off a fresh commit.

The D3 lane from the original incident (pointer on row 1 of 3, deliverable under
`dispatch-57a94876/`): after the union fix E4 now reaches that deliverable — its
`dispatch-57a94876` arm itself reports `dead:sentinel_finalized` (`lane_outcome:
died-clean`, sentinel 46 min old), i.e. the arm genuinely finished ~an hour before the
probe, past the 30-min `finished_unlanded` window, so the lane reads
`dead:no_log_artifact` on staleness, not on a wrong directory. The exact
row-1-of-3-with-fresh-deliverable shape is pinned by Test 13 (it was live-fresh at
02:39, stale by the time the union fix landed).

Out-of-scope gap found while probing (NOT fixed here, needs a new identity source):
`LANE-MERGE-SILENTLY-REVERTS-MAIN-01` has a **fresh** `developer.full.md` under
`docs/handoff/dispatch-26a99a6a/` (owner recorded in its `admission-receipt.yaml`,
sig8 = sha256(mission_digest)[:8]) but **no active.yaml row at all**, so
`deliverable_dirs()` resolves only the tid dir and the tool says `dead:no_log_artifact`
about finished unlanded work:

```
$ bash plugins/leadv2/scripts/leadv2-lane-liveness.sh --project-root ~/Projects/leadv2 --lane LANE-MERGE-SILENTLY-REVERTS-MAIN-01 --json
{"lane":"LANE-MERGE-SILENTLY-REVERTS-MAIN-01","verdict":"dead:no_log_artifact",...,"log_path":null,"raw_log_path":null,"pid":null,...}
```

Fixing this requires an identity source that survives row deletion
(dispatch-ledger.jsonl grep, or matching `admission-receipt.yaml` task_ids) — a
different lane; surfaced here so it is not rediscovered as a regression of this one.

## Mutation controls (leadv2-mutation-control.sh, artifacts under mutation-control/)

| # | mutant (one per changed function body) | rc | baseline_rc / mutated_rc | red line |
|---|---|---|---|---|
| 1 | `deliverable_dirs` reverted to tid-dir-only (`for sess in []:`) — the mandatory "resolution back to `docs/handoff/<tid>`" revert | 0 | 0 / 1 | `[TEST] FAIL: Test 10: verdict=dead:no_log_artifact (must be finished_unlanded:<age>s — E4 resolved the wrong dir)` |
| 2 | union reverted to last-row-only (`sessions_all.get(tid) or ...` → `[session] if session else []`) | 0 | 0 / 1 | `[TEST] FAIL: Test 13: verdict=dead:no_log_artifact (must be finished_unlanded:<age>s — last-row-wins hid the dispatch pointer)` |
| 3 | `resolve()` E4 call site blinded (`_deliverable_age = None`) | 0 | 0 / 1 | `[TEST] FAIL: Test 1: verdict=dead:no_log_artifact (must match finished_unlanded:<age>s, never dead:*)` |

Artifacts: `mutation-control/20260904T005616Z-38626.txt`, `20260904T005659Z-78049.txt`,
`20260904T005733Z-14560.txt` (each carries `baseline_rc=0`, `mutated_rc=1`, the red
line, `diff_hash` of the applied mutant and `lane_diff_hash`).

## Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-lane-liveness.sh        -> syntax OK
$ /bin/bash -n plugins/leadv2/scripts/leadv2-lane-liveness.sh   -> OK (bash 3.2)
$ bash -n plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh -> syntax OK
$ awk '/<<.PY./{f=1;next} /^PY$/{f=0} f' leadv2-lane-liveness.sh > /tmp/…py
$ python3 -m py_compile /tmp/…py                                  -> OK (1145 lines)
```

No standalone .py changed (the Python is a heredoc inside the .sh; extracted and
compiled as above). Changed-scope runner result: see RUNALL section below.

## RUNALL: tests/run-all.sh --scope changed

(Runner takes >10 min; result appended below when the foreground-tracked run finished.)

<!-- RUNALL_RESULT -->

## Commits

```
7de54f50 fix(D2-E4-RESOLVES-THE-WRONG-DIR-01): E4 resolves the lane's real handoff dir, not docs/handoff/<tid>
d072d785 test(D2-E4-RESOLVES-THE-WRONG-DIR-01): founder-shaped fixtures — dispatch-dir deliverable, no-deliverable dead, unreadable-dir unknown
5a6b0de2 fix(D2-E4-RESOLVES-THE-WRONG-DIR-01): E4 unions EVERY registry row's pointer, not just the last   (script body committed by the lead's ORPHAN RESCUE; authored in this lane)
b4ad89d9 test(D2-E4-RESOLVES-THE-WRONG-DIR-01): Test 13 — multi-row registry, pointer only on a non-last row
```
